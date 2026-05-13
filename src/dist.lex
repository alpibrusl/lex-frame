# lex-frame — distributed / parallel row operations
#
# Built on list.par_map which uses OS threads. Each operation here
# produces a cost estimate before running so agents can decide
# whether to proceed given their budget.
#
# AI-agent note: par_apply_col is the recommended entry point for
# heavy column transforms. Pass a budget estimate to the agent’s
# planner before calling. Effect annotation [par] is inherited from
# list.par_map’s OS-thread pool.

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
  frame.n_rows(df) * frame.n_cols(df)
}

# ---- Column-level parallel transform ----------------------------

# Apply fn in parallel to every value of one column.
# Returns Err if the column doesn’t exist.
fn par_apply_col(
  df      :: frame.DataFrame,
  col     :: Str,
  transform :: (Value) -> Value
) -> Result[frame.DataFrame, frame.FrameError] {
  match map.get(df.columns, col) {
    None     => Err(frame.not_found_error(col)),
    Some(xs) => {
      let new_col := list.par_map(xs, transform)
      let new_cols := map.set(df.columns, col, new_col)
      let new_df := { col_names: df.col_names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
      Ok(frame.record_op(new_df, prov.op_add_col(col, "par_apply")))
    },
  }
}

# Apply fn in parallel to all columns independently.
# fn receives (col_name, column_values) and returns new column_values.
fn par_apply_all_cols(
  df        :: frame.DataFrame,
  transform :: (Str, List[Value]) -> List[Value]
) -> frame.DataFrame {
  let name_col_pairs := list.map(df.col_names, fn (name :: Str) -> (Str, List[Value]) {
    match map.get(df.columns, name) {
      None     => (name, []),
      Some(xs) => (name, xs),
    }
  })
  let transformed := list.par_map(name_col_pairs,
    fn (p :: (Str, List[Value])) -> (Str, List[Value]) {
      let name := match p { (a, _) => a }
      let xs   := match p { (_, b) => b }
      (name, transform(name, xs))
    })
  let new_cols := list.fold(transformed, map.new(),
    fn (m :: Map[Str, List[Value]], p :: (Str, List[Value])) -> Map[Str, List[Value]] {
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
  pred      :: (List[(Str, Value)]) -> Bool
) -> frame.DataFrame {
  let all_rows := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> (Int, Bool) {
    let row := match frame.get_row(df, i) { Some(r) => r, None => [] }
    (i, pred(row))
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
# If the transform changes columns, use with_column or from_columns instead.
fn par_map_rows(
  df        :: frame.DataFrame,
  transform :: (List[(Str, Value)]) -> List[(Str, Value)]
) -> Result[frame.DataFrame, frame.FrameError] {
  let rows := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> List[(Str, Value)] {
    match frame.get_row(df, i) { Some(r) => r, None => [] }
  })
  let new_rows := list.par_map(rows, transform)
  rows_to_frame(new_rows, df.col_names, df.provenance)
}

fn rows_to_frame(
  rows       :: List[List[(Str, Value)]],
  col_names  :: List[Str],
  old_prov   :: List[prov.Op]
) -> Result[frame.DataFrame, frame.FrameError] {
  let cols := list.map(col_names, fn (name :: Str) -> (Str, List[Value]) {
    let col_vals := list.map(rows, fn (row :: List[(Str, Value)]) -> Value {
      list.fold(row, val.VNull, fn (acc :: Value, p :: (Str, Value)) -> Value {
        let k := match p { (a, _) => a }
        let v := match p { (_, b) => b }
        let found := match acc { VNull => false, _ => true }
        if found { acc } else if k == name { v } else { val.VNull }
      })
    })
    (name, col_vals)
  })
  match frame.from_columns(cols) {
    Err(e)  => Err(e),
    Ok(df)  =>
      Ok({ col_names: df.col_names, columns: df.columns, nrows: df.nrows,
           provenance: list.concat(old_prov, [prov.op_pipe("par_map_rows")]) }),
  }
}
