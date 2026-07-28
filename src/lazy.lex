import "std.list" as list

import "std.str" as str

import "std.int" as int

import "std.float" as float

import "./frame" as frame

import "./select" as select

import "./sort" as sort

import "./group" as group

import "./io" as fio

# ===== Lazy query plans (lex-frame#16) =====
#
# A `Plan` records ops without executing them; `collect` runs the
# whole pipeline with two plan-level rewrites the eager API cannot do:
#
#   1. **Filters first.** Within each segment (delimited by group_agg
#      nodes) every filter runs before every sort/select, regardless
#      of call order — sorts and projections then touch fewer rows.
#   2. **Projection pruning.** When the plan contains a narrowing op
#      (select or group_agg), only the columns the plan actually
#      references are kept from the source — pushed into the parquet
#      reader itself for `scan_parquet` (lex-frame#17), applied as a
#      zero-copy projection right after load for CSV / in-memory
#      sources.
#
# Semantics vs the eager ops (documented, intentional):
#   - A filter on a column that a *later* select drops works under
#     lazy (the filter is hoisted above the select); eager errors.
#   - Lazy validates every column the plan references at collect
#     time: a misspelled sort key inside a pruned plan is a
#     SELECT_UNKNOWN_COLUMN error, where eager `sort_by_fast`
#     silently no-ops.
#   - `df.sort_by` does not guarantee tie order (Polars default), so
#     hoisting a filter above a sort can reorder rows that compare
#     equal on the sort key — same caveat every query optimizer has.
#
# All execution goes through the existing `_fast` ops, so arrow-backed
# sources ride the std.df kernels and list-backed frames use the same
# legacy fallbacks as the eager API.
type Filter = FEqInt((Str, Int)) | FGtInt((Str, Int)) | FLtInt((Str, Int)) | FEqFloat((Str, Float)) | FGtFloat((Str, Float)) | FLtFloat((Str, Float)) | FEqStr((Str, Str)) | FInStr((Str, List[Str])) | FIsNull(Str) | FNotNull(Str) | FDropNulls(List[Str])

type PlanOp = PFilter(Filter) | PSelect(List[Str]) | PSort((Str, Bool)) | PGroupAgg((List[Str], List[group.AggSpec]))

type Source = SrcFrame(frame.DataFrame) | SrcCsv(Str) | SrcParquet(Str)

type Plan = { source :: Source, ops :: List[PlanOp] }

# ===== Builders =====
fn from_frame(df :: frame.DataFrame) -> Plan {
  { source: SrcFrame(df), ops: [] }
}

fn scan_csv(path :: Str) -> Plan {
  { source: SrcCsv(path), ops: [] }
}

fn scan_parquet(path :: Str) -> Plan {
  { source: SrcParquet(path), ops: [] }
}

fn push(p :: Plan, op :: PlanOp) -> Plan {
  { source: p.source, ops: list.cons(op, p.ops) }
}

fn filter_eq_int(p :: Plan, name :: Str, v :: Int) -> Plan {
  push(p, PFilter(FEqInt(name, v)))
}

fn filter_gt_int(p :: Plan, name :: Str, v :: Int) -> Plan {
  push(p, PFilter(FGtInt(name, v)))
}

fn filter_lt_int(p :: Plan, name :: Str, v :: Int) -> Plan {
  push(p, PFilter(FLtInt(name, v)))
}

fn filter_eq_float(p :: Plan, name :: Str, v :: Float) -> Plan {
  push(p, PFilter(FEqFloat(name, v)))
}

fn filter_gt_float(p :: Plan, name :: Str, v :: Float) -> Plan {
  push(p, PFilter(FGtFloat(name, v)))
}

fn filter_lt_float(p :: Plan, name :: Str, v :: Float) -> Plan {
  push(p, PFilter(FLtFloat(name, v)))
}

fn filter_eq_str(p :: Plan, name :: Str, v :: Str) -> Plan {
  push(p, PFilter(FEqStr(name, v)))
}

fn filter_in_str(p :: Plan, name :: Str, vs :: List[Str]) -> Plan {
  push(p, PFilter(FInStr(name, vs)))
}

fn filter_isnull(p :: Plan, name :: Str) -> Plan {
  push(p, PFilter(FIsNull(name)))
}

fn filter_notnull(p :: Plan, name :: Str) -> Plan {
  push(p, PFilter(FNotNull(name)))
}

fn drop_nulls(p :: Plan, cols :: List[Str]) -> Plan {
  push(p, PFilter(FDropNulls(cols)))
}

fn select_cols(p :: Plan, cols :: List[Str]) -> Plan {
  push(p, PSelect(cols))
}

fn sort_by(p :: Plan, name :: Str, asc :: Bool) -> Plan {
  push(p, PSort(name, asc))
}

# One group_agg node carries the full spec list — that is what makes
# multi-aggregation a single df.group_by_agg kernel call
# (lex-frame#18). Note two group_agg nodes in one plan are NOT
# merged: the second aggregates the *output* of the first, which is a
# different computation from one call with both spec lists.
fn group_agg(p :: Plan, keys :: List[Str], specs :: List[group.AggSpec]) -> Plan {
  push(p, PGroupAgg(keys, specs))
}

# ===== Plan analysis =====
fn contains_str(xs :: List[Str], s :: Str) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or x == s
  })
}

fn add_unique(acc :: List[Str], xs :: List[Str]) -> List[Str] {
  list.fold(xs, acc, fn (a :: List[Str], x :: Str) -> List[Str] {
    if contains_str(a, x) {
      a
    } else {
      list.reverse(list.cons(x, list.reverse(a)))
    }
  })
}

fn filter_cols(f :: Filter) -> List[Str] {
  match f {
    FEqInt(n, _) => [n],
    FGtInt(n, _) => [n],
    FLtInt(n, _) => [n],
    FEqFloat(n, _) => [n],
    FGtFloat(n, _) => [n],
    FLtFloat(n, _) => [n],
    FEqStr(n, _) => [n],
    FInStr(n, _) => [n],
    FIsNull(n) => [n],
    FNotNull(n) => [n],
    FDropNulls(cs) => cs,
  }
}

fn op_cols(op :: PlanOp) -> List[Str] {
  match op {
    PFilter(f) => filter_cols(f),
    PSelect(cs) => cs,
    PSort(n, _) => [n],
    PGroupAgg(keys, specs) => add_unique(keys, list.map(specs, fn (s :: group.AggSpec) -> Str {
      s.in_col
    })),
  }
}

# A narrowing op fully determines its own output columns, so nothing
# after it can reach a source column it dropped.
fn is_narrowing(op :: PlanOp) -> Bool {
  match op {
    PFilter(_) => false,
    PSelect(_) => true,
    PSort(_, _) => false,
    PGroupAgg(_, _) => true,
  }
}

# Columns the source must provide: everything referenced up to and
# including the first narrowing op. None = the plan never narrows, so
# every source column is part of the result and pruning is unsound.
fn needed_at_source(ops :: List[PlanOp]) -> Option[List[Str]] {
  needed_walk(ops, [])
}

fn needed_walk(ops :: List[PlanOp], acc :: List[Str]) -> Option[List[Str]] {
  match list.head(ops) {
    None => None,
    Some(op) => {
      let acc2 := add_unique(acc, op_cols(op))
      if is_narrowing(op) {
        Some(acc2)
      } else {
        needed_walk(list.tail(ops), acc2)
      }
    },
  }
}

fn concat_ops(a :: List[PlanOp], b :: List[PlanOp]) -> List[PlanOp] {
  list.fold(list.reverse(a), b, fn (acc :: List[PlanOp], o :: PlanOp) -> List[PlanOp] {
    list.cons(o, acc)
  })
}

fn segment_out(fil_rev :: List[PlanOp], rest_rev :: List[PlanOp]) -> List[PlanOp] {
  concat_ops(list.reverse(fil_rev), list.reverse(rest_rev))
}

# Rewrite: within each group_agg-delimited segment, all filters run
# first (keeping their relative order), then the remaining ops keep
# their relative order. Filters commute with sorts and projections on
# row content — see the tie-order caveat in the module header.
fn hoist_filters(ops :: List[PlanOp]) -> List[PlanOp] {
  hoist_walk(ops, [], [])
}

fn hoist_walk(ops :: List[PlanOp], fil_rev :: List[PlanOp], rest_rev :: List[PlanOp]) -> List[PlanOp] {
  match list.head(ops) {
    None => segment_out(fil_rev, rest_rev),
    Some(op) => match op {
      PFilter(_) => hoist_walk(list.tail(ops), list.cons(op, fil_rev), rest_rev),
      PSelect(_) => hoist_walk(list.tail(ops), fil_rev, list.cons(op, rest_rev)),
      PSort(_, _) => hoist_walk(list.tail(ops), fil_rev, list.cons(op, rest_rev)),
      PGroupAgg(_, _) => concat_ops(segment_out(fil_rev, rest_rev), list.cons(op, hoist_walk(list.tail(ops), [], []))),
    },
  }
}

# ===== Execution =====
fn apply_filter(df :: frame.DataFrame, f :: Filter) -> Result[frame.DataFrame, frame.FrameError] {
  match f {
    FEqInt(n, v) => select.filter_eq_int_fast(df, n, v),
    FGtInt(n, v) => select.filter_gt_int_fast(df, n, v),
    FLtInt(n, v) => select.filter_lt_int_fast(df, n, v),
    FEqFloat(n, v) => select.filter_eq_float_fast(df, n, v),
    FGtFloat(n, v) => select.filter_gt_float_fast(df, n, v),
    FLtFloat(n, v) => select.filter_lt_float_fast(df, n, v),
    FEqStr(n, v) => select.filter_eq_str_fast(df, n, v),
    FInStr(n, vs) => select.filter_in_str_fast(df, n, vs),
    FIsNull(n) => select.filter_isnull_fast(df, n),
    FNotNull(n) => select.filter_notnull_fast(df, n),
    FDropNulls(cs) => select.drop_nulls_fast(df, cs),
  }
}

fn apply_op(df :: frame.DataFrame, op :: PlanOp) -> Result[frame.DataFrame, frame.FrameError] {
  match op {
    PFilter(f) => apply_filter(df, f),
    PSelect(cs) => select.select_cols_fast(df, cs),
    PSort(n, asc) => Ok(sort.sort_by_fast(df, n, asc)),
    PGroupAgg(keys, specs) => group.group_agg_by_keys_fast(df, keys, specs),
  }
}

fn run_ops(df :: frame.DataFrame, ops :: List[PlanOp]) -> Result[frame.DataFrame, frame.FrameError] {
  match list.head(ops) {
    None => Ok(df),
    Some(op) => match apply_op(df, op) {
      Err(e) => Err(e),
      Ok(df2) => run_ops(df2, list.tail(ops)),
    },
  }
}

# Prune (when the plan narrows), then run the rewritten ops.
fn exec_on(df :: frame.DataFrame, ops :: List[PlanOp]) -> Result[frame.DataFrame, frame.FrameError] {
  match needed_at_source(ops) {
    None => run_ops(df, ops),
    Some(cols) => match select.select_cols_fast(df, cols) {
      Err(e) => Err(e),
      Ok(df2) => run_ops(df2, ops),
    },
  }
}

# Pure collect for `from_frame` plans. Scan sources are refused
# (LAZY_SOURCE_NEEDS_READ) instead of widening this signature to
# `[fs_read]` — the same trade write_csv_fast makes. Use `collect`
# for scan_csv / scan_parquet plans.
fn collect_frame(p :: Plan) -> Result[frame.DataFrame, frame.FrameError] {
  match p.source {
    SrcFrame(df) => exec_on(df, hoist_filters(list.reverse(p.ops))),
    SrcCsv(path) => Err(frame.frame_err("LAZY_SOURCE_NEEDS_READ", "this plan scans a file; collect_frame is the pure entry point for from_frame plans — use collect (effect [fs_read]) instead", path)),
    SrcParquet(path) => Err(frame.frame_err("LAZY_SOURCE_NEEDS_READ", "this plan scans a file; collect_frame is the pure entry point for from_frame plans — use collect (effect [fs_read]) instead", path)),
  }
}

# Execute the plan. The `[fs_read]` effect covers the scan sources;
# a `from_frame` plan performs no reads at runtime (use
# `collect_frame` from pure callers).
fn collect(p :: Plan) -> [fs_read] Result[frame.DataFrame, frame.FrameError] {
  let ops := hoist_filters(list.reverse(p.ops))
  match p.source {
    SrcFrame(df) => exec_on(df, ops),
    SrcCsv(path) => match fio.read_csv_fast(path) {
      Err(e) => Err(e),
      Ok(df) => exec_on(df, ops),
    },
    SrcParquet(path) => match needed_at_source(ops) {
      None => match fio.read_parquet(path) {
        Err(e) => Err(e),
        Ok(df) => run_ops(df, ops),
      },
      Some(cols) => match fio.read_parquet_cols(path, cols) {
        Err(e) => Err(e),
        Ok(df) => run_ops(df, ops),
      },
    },
  }
}

# ===== explain =====
fn filter_desc(f :: Filter) -> Str {
  match f {
    FEqInt(n, v) => str.concat(n, str.concat(" == ", int.to_str(v))),
    FGtInt(n, v) => str.concat(n, str.concat(" > ", int.to_str(v))),
    FLtInt(n, v) => str.concat(n, str.concat(" < ", int.to_str(v))),
    FEqFloat(n, v) => str.concat(n, str.concat(" == ", float.to_str(v))),
    FGtFloat(n, v) => str.concat(n, str.concat(" > ", float.to_str(v))),
    FLtFloat(n, v) => str.concat(n, str.concat(" < ", float.to_str(v))),
    FEqStr(n, v) => str.concat(n, str.concat(" == \"", str.concat(v, "\""))),
    FInStr(n, vs) => str.concat(n, str.concat(" in [", str.concat(str.join(vs, ","), "]"))),
    FIsNull(n) => str.concat(n, " is null"),
    FNotNull(n) => str.concat(n, " is not null"),
    FDropNulls(cs) => str.concat("drop_nulls [", str.concat(str.join(cs, ","), "]")),
  }
}

fn op_desc(op :: PlanOp) -> Str {
  match op {
    PFilter(f) => str.concat("filter ", filter_desc(f)),
    PSelect(cs) => str.concat("select [", str.concat(str.join(cs, ","), "]")),
    PSort(n, asc) => str.concat("sort ", str.concat(n, if asc {
      " asc"
    } else {
      " desc"
    })),
    PGroupAgg(keys, specs) => str.concat("group_agg by [", str.concat(str.join(keys, ","), str.concat("] aggs=", int.to_str(list.len(specs))))),
  }
}

fn source_desc(src :: Source, pruned :: Option[List[Str]]) -> Str {
  let base := match src {
    SrcFrame(_) => "frame",
    SrcCsv(path) => str.concat("scan_csv ", path),
    SrcParquet(path) => str.concat("scan_parquet ", path),
  }
  match pruned {
    None => base,
    Some(cols) => str.concat(base, str.concat(" project=[", str.concat(str.join(cols, ","), "]"))),
  }
}

# The plan as `collect` will actually run it — source line (with the
# pruned projection, if any) followed by one line per rewritten op.
fn explain(p :: Plan) -> List[Str] {
  let ops := hoist_filters(list.reverse(p.ops))
  list.cons(source_desc(p.source, needed_at_source(ops)), list.map(ops, fn (op :: PlanOp) -> Str {
    op_desc(op)
  }))
}

