# lex-frame — column/row selection, filtering, renaming
#
# All operations that reshape a DataFrame without aggregating.
# Each returns a new DataFrame with provenance updated.

import "std.list" as list
import "std.map"  as map
import "std.str"  as str
import "./value"      as val
import "./frame"      as frame
import "./provenance" as prov

# Keep only the named columns (in order given).
fn select_cols(df :: frame.DataFrame, names :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let missing := list.find(names, fn (n :: Str) -> Bool { not frame.has_column(df, n) })
  match missing {
    Some(n) => Err(frame.not_found_error(n)),
    None    => {
      let new_cols := list.fold(names, map.new(),
        fn (m :: Map[Str, List[Value]], name :: Str) -> Map[Str, List[Value]] {
          match map.get(df.columns, name) {
            None      => m,
            Some(col) => map.set(m, name, col),
          }
        })
      let new_df := { col_names: names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
      Ok(frame.record_op(new_df, prov.op_select(names)))
    },
  }
}

# Drop the named columns; silently ignores names not present.
fn drop_cols(df :: frame.DataFrame, names :: List[Str]) -> frame.DataFrame {
  let new_names := list.filter(df.col_names, fn (n :: Str) -> Bool {
    not list.any(names, fn (d :: Str) -> Bool { d == n })
  })
  let new_cols := list.fold(new_names, map.new(),
    fn (m :: Map[Str, List[Value]], n :: Str) -> Map[Str, List[Value]] {
      match map.get(df.columns, n) {
        None      => m,
        Some(col) => map.set(m, n, col),
      }
    })
  let new_df := { col_names: new_names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
  frame.record_op(new_df, prov.op_drop(names))
}

# Rename one column. Fails if from_col doesn't exist or to_col already does.
fn rename_col(df :: frame.DataFrame, from_col :: Str, to_col :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  if not frame.has_column(df, from_col) { Err(frame.not_found_error(from_col)) }
  else if frame.has_column(df, to_col) { Err(frame.duplicate_col_error(to_col)) }
  else {
    let new_names := list.map(df.col_names, fn (n :: Str) -> Str {
      if n == from_col { to_col } else { n }
    })
    let new_cols := list.fold(new_names, map.new(),
      fn (m :: Map[Str, List[Value]], n :: Str) -> Map[Str, List[Value]] {
        let src := if n == to_col { from_col } else { n }
        match map.get(df.columns, src) {
          None      => m,
          Some(col) => map.set(m, n, col),
        }
      })
    let new_df := { col_names: new_names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
    Ok(frame.record_op(new_df, prov.op_rename(from_col, to_col)))
  }
}

# Filter rows by a predicate over row key-value pairs.
# pred_desc is a human-readable description recorded in provenance
# so agents can explain what filter was applied.
fn filter_rows(
  df        :: frame.DataFrame,
  pred_desc :: Str,
  pred      :: (List[(Str, Value)]) -> Bool
) -> frame.DataFrame {
  let kept_indices := list.filter(frame.range_list(0, df.nrows), fn (i :: Int) -> Bool {
    match frame.get_row(df, i) {
      None    => false,
      Some(r) => pred(r),
    }
  })
  let sub := frame.pick_rows(df, kept_indices)
  frame.record_op(sub, prov.op_filter(pred_desc, list.len(kept_indices)))
}

# Filter rows by a single column's value.
# Agent-friendly: takes a column name (validated) + predicate on Value.
fn filter_col(
  df        :: frame.DataFrame,
  col       :: Str,
  pred_desc :: Str,
  pred      :: (Value) -> Bool
) -> Result[frame.DataFrame, frame.FrameError] {
  match frame.get_column(df, col) {
    None     => Err(frame.not_found_error(col)),
    Some(xs) => {
      let kept := list.filter(list.enumerate(xs), fn (p :: (Int, Value)) -> Bool {
        let v := match p { (_, b) => b }
        pred(v)
      })
      let indices := list.map(kept, fn (p :: (Int, Value)) -> Int { match p { (a, _) => a } })
      let sub := frame.pick_rows(df, indices)
      Ok(frame.record_op(sub, prov.op_filter(str.concat(col, str.concat(" ", pred_desc)), list.len(indices))))
    },
  }
}

# Derive a new column from a function over each row.
fn with_column(
  df       :: frame.DataFrame,
  name     :: Str,
  expr_desc :: Str,
  derive   :: (List[(Str, Value)]) -> Value
) -> Result[frame.DataFrame, frame.FrameError] {
  let col := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> Value {
    match frame.get_row(df, i) {
      None    => val.VNull,
      Some(r) => derive(r),
    }
  })
  match frame.add_column(df, name, col) {
    Err(e)     => Err(e),
    Ok(new_df) => Ok(frame.record_op(new_df, prov.op_add_col(name, expr_desc))),
  }
}

# Convenience: look up a value by column name in a row tuple-list.
fn row_get(row :: List[(Str, Value)], col :: Str) -> Option[Value] {
  list.fold(row, None, fn (acc :: Option[Value], p :: (Str, Value)) -> Option[Value] {
    match acc {
      Some(_) => acc,
      None    => {
        let k := match p { (a, _) => a }
        let v := match p { (_, b) => b }
        if k == col { Some(v) } else { None }
      },
    }
  })
}

fn row_get_or_null(row :: List[(Str, Value)], col :: Str) -> Value {
  match row_get(row, col) { Some(v) => v, None => val.VNull }
}
