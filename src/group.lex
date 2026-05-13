# lex-frame — group-by and aggregation
#
# group_by(df, col) collects row indices by key, producing a
# GroupedFrame. agg then applies AggOp functions to each group,
# returning a new flat DataFrame.
#
# Keys are stringified for map storage; original Value is recovered
# via val.parse_str so the group key column has the correct type.

import "std.list" as list
import "std.map"  as map
import "std.str"  as str
import "std.int"  as int
import "./value"      as val
import "./frame"      as frame
import "./agg"        as agg
import "./provenance" as prov

type AggOp =
    AggSum
  | AggMean
  | AggMin
  | AggMax
  | AggCount
  | AggCountNonNull
  | AggStd
  | AggVar
  | AggNDistinct

type AggSpec = { out_col :: Str, in_col :: Str, op :: AggOp }

fn agg_spec(out_col :: Str, in_col :: Str, op :: AggOp) -> AggSpec {
  { out_col: out_col, in_col: in_col, op: op }
}

# A grouped frame: one sub-frame per distinct key value.
type GroupEntry = {
  key_str  :: Str,
  key_val  :: val.Value,
  subframe :: frame.DataFrame,
}

type GroupedFrame = {
  group_col :: Str,
  groups    :: List[GroupEntry],
}

# Group by a single column. Returns Err if column doesn't exist.
fn group_by(df :: frame.DataFrame, col :: Str) -> Result[GroupedFrame, frame.FrameError] {
  match map.get(df.columns, col) {
    None          => Err(frame.not_found_error(col)),
    Some(key_col) => {
      # Build Map[Str, List[Int]]: key_str -> row indices (stored in reverse for efficiency).
      let idx_map := list.fold(list.enumerate(key_col), map.new(),
        fn (m :: Map[Str, List[Int]], p :: (Int, val.Value)) -> Map[Str, List[Int]] {
          let i := match p { (a, _) => a }
          let v := match p { (_, b) => b }
          let k := val.to_str(v)
          let existing := match map.get(m, k) { Some(xs) => xs, None => [] }
          map.set(m, k, list.cons(i, existing))
        })
      # Convert map entries to GroupEntry list.
      let groups_rev := map.fold(idx_map, [],
        fn (acc :: List[GroupEntry], k :: Str, indices :: List[Int]) -> List[GroupEntry] {
          let sub   := frame.pick_rows(df, list.reverse(indices))
          let entry := { key_str: k, key_val: val.parse_str(k), subframe: sub }
          list.cons(entry, acc)
        })
      let groups := list.reverse(groups_rev)
      Ok({ group_col: col, groups: groups })
    },
  }
}

# Aggregate a GroupedFrame. specs describes which output columns to produce.
# Each AggSpec has: out_col (name in result), in_col (source column), op.
# The result always has the group key column first, then the agg columns.
fn agg(gf :: GroupedFrame, specs :: List[AggSpec]) -> frame.DataFrame {
  let n := list.len(gf.groups)
  # Build key column from group key values.
  let key_col  := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value { g.key_val })
  # Build one column per spec by applying the agg op to each group's sub-column.
  let agg_cols := list.map(specs, fn (spec :: AggSpec) -> (Str, List[val.Value]) {
    let values := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
      apply_agg_op(g.subframe, spec.in_col, spec.op)
    })
    (spec.out_col, values)
  })
  let all_cols := list.cons((gf.group_col, key_col), agg_cols)
  match frame.from_columns(all_cols) {
    Ok(df) => frame.record_op(df, prov.op_group_by([gf.group_col])),
    Err(_) => frame.empty(),
  }
}

# Apply a single AggOp to a column of a sub-frame.
fn apply_agg_op(sub :: frame.DataFrame, col :: Str, op :: AggOp) -> val.Value {
  match op {
    AggSum          => match agg.sum_col(sub, col) { Some(v) => v, None => val.VNull },
    AggMean         => match agg.mean_col(sub, col) { Some(x) => val.VFloat(x), None => val.VNull },
    AggMin          => match agg.min_col(sub, col) { Some(v) => v, None => val.VNull },
    AggMax          => match agg.max_col(sub, col) { Some(v) => v, None => val.VNull },
    AggCount        => val.VInt(agg.count_all(sub, col)),
    AggCountNonNull => val.VInt(agg.count_non_null(sub, col)),
    AggStd          => match agg.std_col(sub, col) { Some(x) => val.VFloat(x), None => val.VNull },
    AggVar          => match agg.variance_col(sub, col) { Some(x) => val.VFloat(x), None => val.VNull },
    AggNDistinct    => val.VInt(agg.n_distinct(sub, col)),
  }
}

# Convenience: value_counts — group by col and count rows per group.
fn value_counts(df :: frame.DataFrame, col :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  match group_by(df, col) {
    Err(e) => Err(e),
    Ok(gf) => Ok(agg(gf, [agg_spec("count", col, AggCount)])),
  }
}
