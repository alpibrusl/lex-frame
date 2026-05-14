# lex-frame — DataFrame type and core operations
#
# Storage: Map[Str, col.Col] — typed columns, no per-cell boxing.
# Public API for construction still accepts List[Value] and infers
# column types automatically via col.col_from_values.

import "std.list" as list
import "std.str"  as str
import "std.map"  as map
import "./value"      as val
import "./col"        as col
import "./provenance" as prov

type DataFrame = {
  col_names  :: List[Str],
  columns    :: Map[Str, col.Col],
  nrows      :: Int,
  provenance :: List[prov.Op],
}

type FrameError = { code :: Str, message :: Str, context :: Str }

fn frame_err(code :: Str, message :: Str, context :: Str) -> FrameError {
  { code: code, message: message, context: context }
}

fn not_found_error(name :: Str) -> FrameError {
  frame_err("FRAME_COLUMN_NOT_FOUND",
    str.concat("column '", str.concat(name, "' not found")), name)
}

fn record_op(df :: DataFrame, op :: prov.Op) -> DataFrame {
  { col_names: df.col_names, columns: df.columns, nrows: df.nrows,
    provenance: list.cons(op, df.provenance) }
}

fn empty() -> DataFrame {
  { col_names: [], columns: map.new(), nrows: 0, provenance: [] }
}

# Build a DataFrame from (name, List[Value]) pairs.
# Column types are inferred automatically.
fn from_columns(pairs :: List[(Str, List[val.Value])]) -> Result[DataFrame, FrameError] {
  if list.is_empty(pairs) {
    Ok(empty())
  } else {
    match list.head(pairs) {
      None             => Ok(empty()),
      Some(first_pair) => {
        let expected := list.len(match first_pair { (_, c) => c })
        let length_ok := list.fold(pairs, true,
          fn (acc :: Bool, pair :: (Str, List[val.Value])) -> Bool {
            acc and list.len(match pair { (_, c) => c }) == expected
          })
        if length_ok {
          let names    := list.map(pairs, fn (p :: (Str, List[val.Value])) -> Str { match p { (n, _) => n } })
          let col_map  := list.fold(pairs, map.new(),
            fn (acc :: Map[Str, col.Col], pair :: (Str, List[val.Value])) -> Map[Str, col.Col] {
              let name := match pair { (n, _) => n }
              let vals := match pair { (_, c) => c }
              map.set(acc, name, col.col_from_values(vals))
            })
          Ok({ col_names: names, columns: col_map, nrows: expected,
               provenance: [prov.op_load("<from_columns>", expected)] })
        } else {
          let bad := list.fold(pairs, None,
            fn (acc :: Option[Str], pair :: (Str, List[val.Value])) -> Option[Str] {
              match acc {
                Some(_) => acc,
                None    => {
                  let n := match pair { (nm, _) => nm }
                  let c := match pair { (_, cv) => cv }
                  if list.len(c) != expected { Some(n) } else { None }
                },
              }
            })
          match bad {
            None    => Err(frame_err("FRAME_LENGTH_MISMATCH", "column length mismatch", "")),
            Some(n) => Err(frame_err("FRAME_LENGTH_MISMATCH",
              str.concat("column '", str.concat(n, "' has wrong length")), n)),
          }
        }
      },
    }
  }
}

# Build a DataFrame from pre-typed (name, Col) pairs.
fn from_typed_columns(pairs :: List[(Str, col.Col)]) -> Result[DataFrame, FrameError] {
  if list.is_empty(pairs) {
    Ok(empty())
  } else {
    match list.head(pairs) {
      None             => Ok(empty()),
      Some(first_pair) => {
        let expected := col.col_len(match first_pair { (_, c) => c })
        let length_ok := list.fold(pairs, true,
          fn (acc :: Bool, pair :: (Str, col.Col)) -> Bool {
            acc and col.col_len(match pair { (_, c) => c }) == expected
          })
        if length_ok {
          let names   := list.map(pairs, fn (p :: (Str, col.Col)) -> Str { match p { (n, _) => n } })
          let col_map := list.fold(pairs, map.new(),
            fn (acc :: Map[Str, col.Col], pair :: (Str, col.Col)) -> Map[Str, col.Col] {
              let name := match pair { (n, _) => n }
              let c    := match pair { (_, c) => c }
              map.set(acc, name, c)
            })
          Ok({ col_names: names, columns: col_map, nrows: expected, provenance: [] })
        } else {
          Err(frame_err("FRAME_LENGTH_MISMATCH", "column length mismatch", ""))
        }
      },
    }
  }
}

# Element access — returns Value for cross-column row operations.
fn nth_value(c :: col.Col, idx :: Int) -> val.Value {
  col.col_nth(c, idx)
}

# Pick rows by index list, preserving column types.
fn pick_rows(df :: DataFrame, indices :: List[Int]) -> DataFrame {
  let new_map := list.fold(df.col_names, map.new(),
    fn (acc :: Map[Str, col.Col], name :: Str) -> Map[Str, col.Col] {
      match map.get(df.columns, name) {
        None    => acc,
        Some(c) => map.set(acc, name, col.col_pick(c, indices)),
      }
    })
  { col_names: df.col_names, columns: new_map, nrows: list.len(indices),
    provenance: df.provenance }
}

fn range_list(start :: Int, stop :: Int) -> List[Int] {
  if start >= stop { [] }
  else { list.cons(start, range_list(start + 1, stop)) }
}

fn get_row(df :: DataFrame, idx :: Int) -> List[(Str, val.Value)] {
  list.map(df.col_names, fn (name :: Str) -> (Str, val.Value) {
    match map.get(df.columns, name) {
      None    => (name, val.vnull()),
      Some(c) => (name, col.col_nth(c, idx)),
    }
  })
}

fn head(df :: DataFrame, n :: Int) -> DataFrame {
  let actual := if n > df.nrows { df.nrows } else { n }
  let df2    := pick_rows(df, range_list(0, actual))
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
    provenance: list.cons(prov.op_head(n), df.provenance) }
}

fn tail(df :: DataFrame, n :: Int) -> DataFrame {
  let start := if n >= df.nrows { 0 } else { df.nrows - n }
  let df2   := pick_rows(df, range_list(start, df.nrows))
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
    provenance: list.cons(prov.op_tail(n), df.provenance) }
}

fn slice_rows(df :: DataFrame, start :: Int, stop :: Int) -> DataFrame {
  let actual_stop := if stop > df.nrows { df.nrows } else { stop }
  let df2 := pick_rows(df, range_list(start, actual_stop))
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
    provenance: list.cons(prov.op_slice(start, stop), df.provenance) }
}

# Add a column given a List[Value] (type-inferred).
fn add_column(df :: DataFrame, name :: Str, vals :: List[val.Value]) -> Result[DataFrame, FrameError] {
  if list.len(vals) != df.nrows {
    Err(frame_err("FRAME_LENGTH_MISMATCH",
      str.concat("column '", str.concat(name, "' has wrong length")), name))
  } else {
    let new_names := list.reverse(list.cons(name, list.reverse(df.col_names)))
    Ok({ col_names: new_names,
         columns: map.set(df.columns, name, col.col_from_values(vals)),
         nrows: df.nrows,
         provenance: list.cons(prov.op_add_column(name), df.provenance) })
  }
}

# Add a pre-typed column.
fn add_typed_column(df :: DataFrame, name :: Str, c :: col.Col) -> Result[DataFrame, FrameError] {
  if col.col_len(c) != df.nrows {
    Err(frame_err("FRAME_LENGTH_MISMATCH",
      str.concat("column '", str.concat(name, "' has wrong length")), name))
  } else {
    let new_names := list.reverse(list.cons(name, list.reverse(df.col_names)))
    Ok({ col_names: new_names,
         columns: map.set(df.columns, name, c),
         nrows: df.nrows,
         provenance: list.cons(prov.op_add_column(name), df.provenance) })
  }
}

fn drop_column(df :: DataFrame, name :: Str) -> Result[DataFrame, FrameError] {
  let missing := list.fold(df.col_names, true, fn (acc :: Bool, n :: Str) -> Bool {
    acc and n != name
  })
  if missing {
    Err(not_found_error(name))
  } else {
    let new_names := list.filter(df.col_names, fn (n :: Str) -> Bool { n != name })
    Ok({ col_names: new_names, columns: df.columns, nrows: df.nrows,
         provenance: list.cons(prov.op_drop([name]), df.provenance) })
  }
}

fn pipe(df :: DataFrame, step_name :: Str, transform :: (DataFrame) -> DataFrame) -> DataFrame {
  let df2 := transform(df)
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows,
    provenance: list.cons(prov.op_pipe(step_name), df2.provenance) }
}
