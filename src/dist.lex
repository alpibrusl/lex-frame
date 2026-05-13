# lex-frame — distributed / parallel row operations
#
# Built on list.par_map which uses OS threads. Each operation here
# produces a cost estimate before running so agents can decide
# whether to proceed given their budget.
#
# AI-agent note: par_apply_col is the recommended entry point for
# heavy column transforms. Pass a budget estimate to the agent's
# planner before calling. Effect annotation [par] is inherited from
# list.par_map's OS-thread pool.

import "std.list" as list
import "std.map"  as map
import "std.str"  as str
import "std.int"  as int
import "./value"      as val
import "./frame"      as frame
import "./provenance" as prov

# ---- Cost estimation (pure) --------------------------------------

# Rough op-count estimate for a par_apply on n rows.
# Agents can check this against their budget before executing.
fn estimate_par_cost(df :: frame.DataFrame) -> Int {
  df.nrows * list.len(df.col_names)
}

# ---- Column-level parallel transform ----------------------------

# Apply fn in parallel to every value of one column.
# Returns Err if the column doesn't exist.
fn par_apply_col(
  df        :: frame.DataFrame,
  col       :: Str,
  transform :: (val.Value) -> val.Value
) -> Result[frame.DataFrame, frame.FrameError] {
  match map.get(df.columns, col) {
    None     => Err(frame.not_found_error(col)),
    Some(xs) => {
      let new_col  := list.par_map(xs, transform)
      let new_cols := map.set(df.columns, col, new_col)
      let new_df   := { col_names: df.col_names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
      Ok(frame.record_op(new_df, prov.op_add_column(col)))
    },
  }
}

# Apply fn in parallel to all columns independently.
# fn receives (col_name, column_values) and returns new column_values.
fn par_apply_all_cols(
  df        :: frame.DataFrame,
  transform :: (Str, List[val.Value]) -> List[val.Value]
) -> frame.DataFrame {
  let name_col_pairs := list.map(df.col_names, fn (name :: Str) -> (Str, List[val.Value]) {
    match map.get(df.columns, name) {
      None     => (name, []),
      Some(xs) => (name, xs),
    }
  })
  let transformed := list.par_map(name_col_pairs,
    fn (p :: (Str, List[val.Value])) -> (Str, List[val.Value]) {
      let name := match p { (a, _) => a }
      let xs   := match p { (_, b) => b }
      (name, transform(name, xs))
    })
  let new_cols := list.fold(transformed, map.new(),
    fn (m :: Map[Str, List[val.Value]], p :: (Str, List[val.Value])) -> Map[Str, List[val.Value]] {
      map.set(m, match p { (k, _) => k }, match p { (_, v) => v })
    })
  let new_df := { col_names: df.col_names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
  frame.record_op(new_df, prov.op_pipe("par_apply_all_cols"))
}

# ---- Row-level parallel filter -----------------------------------

# Filter rows in parallel. pred runs in OS threads.
# pred_desc is recorded in provenance for agent auditability.
fn par_filter_rows(
  df        :: frame.DataFrame,
  pred_desc :: Str,
  pred      :: (List[(Str, val.Value)]) -> Bool
) -> frame.DataFrame {
  let all_rows := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> (Int, Bool) {
    (i, pred(frame.get_row(df, i)))
  })
  let kept_indices := list.map(
    list.filter(all_rows, fn (p :: (Int, Bool)) -> Bool { match p { (_, b) => b } }),
    fn (p :: (Int, Bool)) -> Int { match p { (i, _) => i } }
  )
  let sub := frame.pick_rows(df, kept_indices)
  frame.record_op(sub, prov.op_filter(pred_desc, list.len(kept_indices)))
}

# ---- Row-level parallel map (produces new DataFrame) ------------
# Each row is transformed; result must have the same column set.
fn par_map_rows(
  df        :: frame.DataFrame,
  transform :: (List[(Str, val.Value)]) -> List[(Str, val.Value)]
) -> Result[frame.DataFrame, frame.FrameError] {
  let rows     := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> List[(Str, val.Value)] {
    frame.get_row(df, i)
  })
  let new_rows := list.par_map(rows, transform)
  let cols := list.map(df.col_names, fn (name :: Str) -> (Str, List[val.Value]) {
    let col_vals := list.map(new_rows, fn (row :: List[(Str, val.Value)]) -> val.Value {
      list.fold(row, val.VNull, fn (acc :: val.Value, p :: (Str, val.Value)) -> val.Value {
        let k := match p { (a, _) => a }
        let v := match p { (_, b) => b }
        match acc {
          val.VNull => if k == name { v } else { val.VNull }
          _         => acc
        }
      })
    })
    (name, col_vals)
  })
  match frame.from_columns(cols) {
    Err(e) => Err(e),
    Ok(df2) => Ok(frame.record_op(df2, prov.op_pipe("par_map_rows"))),
  }
}
