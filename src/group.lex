import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.df" as dfq

import "./value" as val

import "./col" as col

import "./frame" as frame

import "./agg" as agg

import "./provenance" as prov

type AggOp = AggSum | AggMean | AggMin | AggMax | AggCount | AggCountNonNull | AggStd | AggVar | AggNDistinct

type AggSpec = { out_col :: Str, in_col :: Str, op :: AggOp }

fn agg_sum() -> AggOp {
  AggSum
}

fn agg_mean() -> AggOp {
  AggMean
}

fn agg_min() -> AggOp {
  AggMin
}

fn agg_max() -> AggOp {
  AggMax
}

fn agg_count() -> AggOp {
  AggCount
}

fn agg_count_non_null() -> AggOp {
  AggCountNonNull
}

fn agg_std() -> AggOp {
  AggStd
}

fn agg_var() -> AggOp {
  AggVar
}

fn agg_n_distinct() -> AggOp {
  AggNDistinct
}

fn agg_spec(out_col :: Str, in_col :: Str, op :: AggOp) -> AggSpec {
  { out_col: out_col, in_col: in_col, op: op }
}

type GroupEntry = { key_str :: Str, key_val :: val.Value, subframe :: frame.DataFrame }

type GroupedFrame = { group_col :: Str, groups :: List[GroupEntry] }

fn group_by(df :: frame.DataFrame, col_name :: Str) -> Result[GroupedFrame, frame.FrameError] {
  match map.get(df.columns, col_name) {
    None => Err(frame.not_found_error(col_name)),
    Some(c) => {
      let key_vals := col.col_to_values(c)
      let idx_map := list.fold(list.enumerate(key_vals), map.new(), fn (m :: Map[Str, List[Int]], p :: (Int, val.Value)) -> Map[Str, List[Int]] {
        let i := match p {
          (a, _) => a,
        }
        let v := match p {
          (_, b) => b,
        }
        let k := val.to_str(v)
        let existing := match map.get(m, k) {
          Some(xs) => xs,
          None => [],
        }
        map.set(m, k, list.cons(i, existing))
      })
      let groups := list.reverse(list.fold(map.entries(idx_map), [], fn (acc :: List[GroupEntry], pair :: (Str, List[Int])) -> List[GroupEntry] {
        let k := match pair {
          (a, _) => a,
        }
        let indices := match pair {
          (_, b) => b,
        }
        let sub := frame.pick_rows(df, list.reverse(indices))
        list.cons({ key_str: k, key_val: val.parse_str(k), subframe: sub }, acc)
      }))
      Ok({ group_col: col_name, groups: groups })
    },
  }
}

fn agg(gf :: GroupedFrame, specs :: List[AggSpec]) -> frame.DataFrame {
  let key_vals := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
    g.key_val
  })
  let agg_cols := list.map(specs, fn (spec :: AggSpec) -> (Str, List[val.Value]) {
    let vals := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
      apply_agg_op(g.subframe, spec.in_col, spec.op)
    })
    (spec.out_col, vals)
  })
  let all_cols := list.cons((gf.group_col, key_vals), agg_cols)
  match frame.from_columns(all_cols) {
    Ok(df) => frame.record_op(df, prov.op_group_by([gf.group_col])),
    Err(_) => frame.empty(),
  }
}

fn apply_agg_op(sub :: frame.DataFrame, col_name :: Str, op :: AggOp) -> val.Value {
  match op {
    AggSum => match agg.sum_col(sub, col_name) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggMean => match agg.mean_col(sub, col_name) {
      Some(f) => val.vfloat(f),
      None => val.vnull(),
    },
    AggMin => match agg.min_col(sub, col_name) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggMax => match agg.max_col(sub, col_name) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggCount => val.vint(agg.count_all(sub, col_name)),
    AggCountNonNull => val.vint(agg.count_non_null(sub, col_name)),
    AggStd => match agg.std_col(sub, col_name) {
      Some(f) => val.vfloat(f),
      None => val.vnull(),
    },
    AggVar => match agg.variance_col(sub, col_name) {
      Some(f) => val.vfloat(f),
      None => val.vnull(),
    },
    AggNDistinct => val.vint(agg.n_distinct(sub, col_name)),
  }
}

# Map an AggOp to the op string df.group_by_agg accepts. AggStd /
# AggVar / AggCountNonNull have no df kernel yet — those return None
# and `group_agg_fast` reports GROUP_UNSUPPORTED_FAST_AGG for them
# on arrow-backed frames (the legacy path still supports all nine).
fn agg_op_to_df_op(op :: AggOp) -> Option[Str] {
  match op {
    AggSum => Some("sum"),
    AggMean => Some("mean"),
    AggMin => Some("min"),
    AggMax => Some("max"),
    AggCount => Some("count"),
    AggNDistinct => Some("n_distinct"),
    AggCountNonNull => None,
    AggStd => None,
    AggVar => None,
  }
}

# Multi-key fast-path group-by + aggregate in one call. Arrow-backed
# frames route through df.group_by_agg (single Polars hash group-by
# over the columnar buffer) with any number of key columns. Legacy
# frames fall back to `group_by` + `agg`, which only supports a
# single key — multi-key on a list-backed frame is an error
# (GROUP_MULTI_KEY_NEEDS_ARROW) rather than a silently wrong answer.
fn group_agg_by_keys_fast(df :: frame.DataFrame, keys :: List[Str], specs :: List[AggSpec]) -> Result[frame.DataFrame, frame.FrameError] {
  let keys_desc := str.join(keys, ",")
  match df.arrow_table {
    None => if list.len(keys) == 1 {
      match list.head(keys) {
        None => Err(frame.frame_err("GROUP_UNKNOWN_KEY", "no group keys given", "")),
        Some(key) => match group_by(df, key) {
          Err(e) => Err(e),
          Ok(gf) => Ok(agg(gf, specs)),
        },
      }
    } else {
      if list.is_empty(keys) {
        Err(frame.frame_err("GROUP_UNKNOWN_KEY", "no group keys given", ""))
      } else {
        Err(frame.frame_err("GROUP_MULTI_KEY_NEEDS_ARROW", "the legacy engine only supports a single group key; build the frame via io.read_csv_fast / io.read_parquet / frame.from_arrow_table for multi-key group-by", keys_desc))
      }
    },
    Some(t) => {
      let mapped := list.fold(specs, Some([]), fn (acc :: Option[List[(Str, Str, Str)]], spec :: AggSpec) -> Option[List[(Str, Str, Str)]] {
        match acc {
          None => None,
          Some(done) => match agg_op_to_df_op(spec.op) {
            None => None,
            Some(op_str) => Some(list.cons((spec.out_col, spec.in_col, op_str), done)),
          },
        }
      })
      match mapped {
        None => Err(frame.frame_err("GROUP_UNSUPPORTED_FAST_AGG", "AggStd / AggVar / AggCountNonNull have no df.group_by_agg kernel; use the legacy group_by + agg path on a list-backed frame", keys_desc)),
        Some(rev_specs) => match dfq.group_by_agg(t, keys, list.reverse(rev_specs)) {
          Err(e) => Err(frame.frame_err("GROUP_UNKNOWN_KEY", e, keys_desc)),
          Ok(t2) => Ok(frame.with_arrow_table(df, t2, prov.op_group_by(keys))),
        },
      }
    },
  }
}

# Single-key convenience wrapper over group_agg_by_keys_fast.
fn group_agg_fast(df :: frame.DataFrame, key :: Str, specs :: List[AggSpec]) -> Result[frame.DataFrame, frame.FrameError] {
  group_agg_by_keys_fast(df, [key], specs)
}

fn value_counts(df :: frame.DataFrame, col_name :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  match group_by(df, col_name) {
    Err(e) => Err(e),
    Ok(gf) => Ok(agg(gf, [agg_spec("count", col_name, AggCount)])),
  }
}

