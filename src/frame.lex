# Core DataFrame type and fundamental operations.

import "std.list" as list
import "std.str"  as str
import "std.map"  as map
import "std.int"  as int
import "./value"      as val
import "./provenance" as prov

type DataFrame = {
  col_names  :: List[Str],
  columns    :: Map[Str, List[val.Value]],
  nrows      :: Int,
  provenance :: List[prov.Op],
}

type FrameError = {
  code    :: Str,
  message :: Str,
  context :: Str,
}

fn frame_err(code :: Str, message :: Str, context :: Str) -> FrameError {
  { code: code, message: message, context: context }
}

fn empty() -> DataFrame {
  { col_names: [], columns: map.new(), nrows: 0, provenance: [] }
}

fn from_columns(cols :: List[(Str, List[val.Value])]) -> Result[DataFrame, FrameError] {
  if list.is_empty(cols) {
    Ok(empty())
  } else {
    match list.head(cols) {
      None => Ok(empty()),
      Some(first_pair) => {
        let expected := match first_pair { (_, c) => list.len(c) }
        let length_ok := list.all(cols, fn (pair :: (Str, List[val.Value])) -> Bool {
          match pair { (_, c) => list.len(c) == expected }
        })
        if length_ok {
          let names := list.map(cols, fn (pair :: (Str, List[val.Value])) -> Str {
            match pair { (name, _) => name }
          })
          let cols_map := list.fold(cols, map.new(),
            fn (acc :: Map[Str, List[val.Value]], pair :: (Str, List[val.Value])) -> Map[Str, List[val.Value]] {
              match pair { (name, c) => map.set(acc, name, c) }
            })
          let op := prov.op_load("<from_columns>", expected)
          Ok({ col_names: names, columns: cols_map, nrows: expected, provenance: [op] })
        } else {
          let bad := list.find(cols, fn (pair :: (Str, List[val.Value])) -> Bool {
            match pair { (_, c) => list.len(c) != expected }
          })
          match bad {
            None    => Err(frame_err("FRAME_LENGTH_MISMATCH", "column length mismatch", "")),
            Some(p) => match p {
              (bad_name, _) =>
                Err(frame_err("FRAME_LENGTH_MISMATCH",
                  str.concat("column '", str.concat(bad_name, "' has wrong length")),
                  bad_name))
            },
          }
        }
      },
    }
  }
}

# Safe index into a column using a (found, value) accumulator.
fn nth_value(col :: List[val.Value], idx :: Int) -> val.Value {
  let result := list.fold(list.enumerate(col), (false, val.VNull),
    fn (acc :: (Bool, val.Value), pair :: (Int, val.Value)) -> (Bool, val.Value) {
      match acc {
        (true, v)  => (true, v),
        (false, _) => match pair { (i, v) => if i == idx { (true, v) } else { (false, val.VNull) } },
      }
    })
  match result { (_, v) => v }
}

fn pick_by_indices(col :: List[val.Value], indices :: List[Int]) -> List[val.Value] {
  list.map(indices, fn (idx :: Int) -> val.Value { nth_value(col, idx) })
}

fn pick_rows(df :: DataFrame, indices :: List[Int]) -> DataFrame {
  let new_map := list.fold(df.col_names, map.new(),
    fn (acc :: Map[Str, List[val.Value]], name :: Str) -> Map[Str, List[val.Value]] {
      let col := match map.get(df.columns, name) { Some(c) => c, None => [] }
      map.set(acc, name, pick_by_indices(col, indices))
    })
  { col_names: df.col_names, columns: new_map, nrows: list.len(indices), provenance: df.provenance }
}

fn range_list(start :: Int, stop :: Int) -> List[Int] {
  if start >= stop { [] } else { list.cons(start, range_list(start + 1, stop)) }
}

fn get_row(df :: DataFrame, idx :: Int) -> List[(Str, val.Value)] {
  list.map(df.col_names, fn (name :: Str) -> (Str, val.Value) {
    let col := match map.get(df.columns, name) { Some(c) => c, None => [] }
    (name, nth_value(col, idx))
  })
}

fn head(df :: DataFrame, n :: Int) -> DataFrame {
  let actual := if n > df.nrows { df.nrows } else { n }
  let df2 := pick_rows(df, range_list(0, actual))
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
    provenance: list.cons(prov.op_head(n), df.provenance) }
}

fn tail(df :: DataFrame, n :: Int) -> DataFrame {
  let start := if n >= df.nrows { 0 } else { df.nrows - n }
  let df2 := pick_rows(df, range_list(start, df.nrows))
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
    provenance: list.cons(prov.op_tail(n), df.provenance) }
}

fn slice_rows(df :: DataFrame, start :: Int, stop :: Int) -> DataFrame {
  let actual_stop := if stop > df.nrows { df.nrows } else { stop }
  let df2 := pick_rows(df, range_list(start, actual_stop))
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
    provenance: list.cons(prov.op_slice(start, stop), df.provenance) }
}

fn add_column(df :: DataFrame, name :: Str, col :: List[val.Value]) -> Result[DataFrame, FrameError] {
  if list.len(col) != df.nrows {
    Err(frame_err("FRAME_LENGTH_MISMATCH",
      str.concat("column '", str.concat(name, "' has wrong length")), name))
  } else {
    let new_names := list.reverse(list.cons(name, list.reverse(df.col_names)))
    Ok({ col_names: new_names, columns: map.set(df.columns, name, col), nrows: df.nrows,
         provenance: list.cons(prov.op_add_column(name), df.provenance) })
  }
}

fn drop_column(df :: DataFrame, name :: Str) -> Result[DataFrame, FrameError] {
  if list.all(df.col_names, fn (n :: Str) -> Bool { n != name }) {
    Err(frame_err("FRAME_COLUMN_NOT_FOUND",
      str.concat("column '", str.concat(name, "' not found")), name))
  } else {
    let new_names := list.filter(df.col_names, fn (n :: Str) -> Bool { n != name })
    Ok({ col_names: new_names, columns: df.columns, nrows: df.nrows,
         provenance: list.cons(prov.op_drop([name]), df.provenance) })
  }
}

fn pipe(df :: DataFrame, step_name :: Str, transform :: fn(DataFrame) -> DataFrame) -> DataFrame {
  let df2 := transform(df)
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
    provenance: list.cons(prov.op_pipe(step_name), df2.provenance) }
}
