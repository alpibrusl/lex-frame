# lex-frame — column/row selection and filtering

import "std.list" as list
import "std.str"  as str
import "std.map"  as map
import "./value"      as val
import "./col"        as col
import "./frame"      as frame
import "./provenance" as prov

fn row_get_or_null(row :: List[(Str, val.Value)], name :: Str) -> val.Value {
  match list.fold(row, None,
    fn (acc :: Option[(Str, val.Value)], pair :: (Str, val.Value)) -> Option[(Str, val.Value)] {
      match acc {
        Some(_) => acc,
        None    => if match pair { (k, _) => k == name } { Some(pair) } else { None },
      }
    }) {
    None    => val.vnull(),
    Some(p) => match p { (_, v) => v },
  }
}

fn row_get(row :: List[(Str, val.Value)], name :: Str) -> Option[val.Value] {
  match list.fold(row, None,
    fn (acc :: Option[(Str, val.Value)], pair :: (Str, val.Value)) -> Option[(Str, val.Value)] {
      match acc {
        Some(_) => acc,
        None    => if match pair { (k, _) => k == name } { Some(pair) } else { None },
      }
    }) {
    None    => None,
    Some(p) => match p { (_, v) => Some(v) },
  }
}

fn select_cols(df :: frame.DataFrame, wanted :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let missing := list.filter(wanted, fn (name :: Str) -> Bool {
    list.fold(df.col_names, true, fn (acc :: Bool, n :: Str) -> Bool { acc and n != name })
  })
  if list.is_empty(missing) {
    let new_map := list.fold(wanted, map.new(),
      fn (acc :: Map[Str, col.Col], name :: Str) -> Map[Str, col.Col] {
        match map.get(df.columns, name) {
          None    => acc,
          Some(c) => map.set(acc, name, c),
        }
      })
    Ok({ col_names: wanted, columns: new_map, nrows: df.nrows,
         provenance: list.cons(prov.op_select(wanted), df.provenance) })
  } else {
    let first := match list.head(missing) { Some(n) => n, None => "" }
    Err(frame.frame_err("SELECT_UNKNOWN_COLUMN",
      str.concat("column '", str.concat(first, "' not found")), first))
  }
}

fn drop_cols(df :: frame.DataFrame, to_drop :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let keep := list.filter(df.col_names, fn (name :: Str) -> Bool {
    list.fold(to_drop, true, fn (acc :: Bool, d :: Str) -> Bool { acc and d != name })
  })
  select_cols(df, keep)
}

fn rename_col(df :: frame.DataFrame, old_name :: Str, new_name :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  let missing := list.fold(df.col_names, true, fn (acc :: Bool, n :: Str) -> Bool { acc and n != old_name })
  if missing {
    Err(frame.frame_err("FRAME_COLUMN_NOT_FOUND",
      str.concat("column '", str.concat(old_name, "' not found")), old_name))
  } else {
    let new_names := list.map(df.col_names, fn (n :: Str) -> Str {
      if n == old_name { new_name } else { n }
    })
    let old_col := match map.get(df.columns, old_name) {
      Some(c) => c,
      None    => col.col_str([]),
    }
    let new_map := map.set(df.columns, new_name, old_col)
    Ok({ col_names: new_names, columns: new_map, nrows: df.nrows,
         provenance: list.cons(prov.op_rename(old_name, new_name), df.provenance) })
  }
}

fn filter_rows(df :: frame.DataFrame, pred_desc :: Str, pred :: (List[(Str, val.Value)]) -> Bool) -> Result[frame.DataFrame, frame.FrameError] {
  let kept := list.filter(frame.range_list(0, df.nrows), fn (i :: Int) -> Bool {
    pred(frame.get_row(df, i))
  })
  let df2 := frame.pick_rows(df, kept)
  Ok({ col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
       provenance: list.cons(prov.op_filter(pred_desc, df2.nrows), df.provenance) })
}

fn with_column(df :: frame.DataFrame, name :: Str, derive :: (List[(Str, val.Value)]) -> val.Value) -> Result[frame.DataFrame, frame.FrameError] {
  let new_vals := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> val.Value {
    derive(frame.get_row(df, i))
  })
  frame.add_column(df, name, new_vals)
}
