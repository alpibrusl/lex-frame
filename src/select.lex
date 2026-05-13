# Column selection, filtering, and derived column operations.

import "std.list" as list
import "std.str"  as str
import "std.map"  as map
import "./value" as val
import "./frame" as frame
import "./provenance" as prov

fn row_get(row :: List[(Str, val.Value)], col :: Str) -> Option[val.Value] {
  list.find(row, fn (pair :: (Str, val.Value)) -> Bool {
    match pair { (k, _) => k == col }
  }) |> fn (opt :: Option[(Str, val.Value)]) -> Option[val.Value] {
    match opt { None => None, Some(p) => match p { (_, v) => Some(v) } }
  }
}

fn row_get_or_null(row :: List[(Str, val.Value)], col :: Str) -> val.Value {
  match list.find(row, fn (pair :: (Str, val.Value)) -> Bool {
    match pair { (k, _) => k == col }
  }) {
    None    => val.VNull,
    Some(p) => match p { (_, v) => v },
  }
}

fn select_cols(df :: frame.DataFrame, wanted :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let missing := list.filter(wanted, fn (name :: Str) -> Bool {
    list.all(df.col_names, fn (n :: Str) -> Bool { n != name })
  })
  if list.is_empty(missing) {
    let new_cols := list.map(wanted, fn (name :: Str) -> (Str, List[val.Value]) {
      let col := match map.get(df.columns, name) { Some(c) => c, None => [] }
      (name, col)
    })
    let new_map := list.fold(new_cols, map.new(), fn (acc :: Map[Str, List[val.Value]], pair :: (Str, List[val.Value])) -> Map[Str, List[val.Value]] {
      match pair { (name, col) => map.set(acc, name, col) }
    })
    let op := prov.op_select(wanted)
    Ok({ col_names: wanted, columns: new_map, nrows: df.nrows,
         provenance: list.cons(op, df.provenance) })
  } else {
    let first_missing := match list.head(missing) { Some(n) => n, None => "" }
    Err(frame.frame_err("SELECT_UNKNOWN_COLUMN",
      str.concat("column '", str.concat(first_missing, "' not found")),
      first_missing))
  }
}

fn drop_cols(df :: frame.DataFrame, to_drop :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let keep := list.filter(df.col_names, fn (name :: Str) -> Bool {
    list.all(to_drop, fn (d :: Str) -> Bool { d != name })
  })
  select_cols(df, keep)
}

fn rename_col(df :: frame.DataFrame, old_name :: Str, new_name :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  if list.all(df.col_names, fn (n :: Str) -> Bool { n != old_name }) {
    Err(frame.frame_err("FRAME_COLUMN_NOT_FOUND",
      str.concat("column '", str.concat(old_name, "' not found")), old_name))
  } else {
    let new_names := list.map(df.col_names, fn (n :: Str) -> Str {
      if n == old_name { new_name } else { n }
    })
    let old_col := match map.get(df.columns, old_name) { Some(c) => c, None => [] }
    let new_map := map.set(df.columns, new_name, old_col)
    let op := prov.op_rename(old_name, new_name)
    Ok({ col_names: new_names, columns: new_map, nrows: df.nrows,
         provenance: list.cons(op, df.provenance) })
  }
}

fn filter_rows(df :: frame.DataFrame, pred_desc :: Str, pred :: fn(List[(Str, val.Value)]) -> Bool) -> Result[frame.DataFrame, frame.FrameError] {
  let indices := list.filter(
    list.enumerate(frame.range_list(0, df.nrows)),
    fn (pair :: (Int, Int)) -> Bool {
      match pair { (_, i) => pred(frame.get_row(df, i)) }
    }
  )
  let kept_indices := list.map(indices, fn (pair :: (Int, Int)) -> Int {
    match pair { (_, i) => i }
  })
  let df2 := frame.pick_rows(df, kept_indices)
  let op := prov.op_filter(pred_desc, df2.nrows)
  Ok({ col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
       provenance: list.cons(op, df.provenance) })
}

fn with_column(df :: frame.DataFrame, name :: Str, derive :: fn(List[(Str, val.Value)]) -> val.Value) -> Result[frame.DataFrame, frame.FrameError] {
  let new_col := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> val.Value {
    derive(frame.get_row(df, i))
  })
  frame.add_column(df, name, new_col)
}
