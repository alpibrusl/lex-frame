# lex-frame — core DataFrame type and fundamental operations
#
# AI-agent-first design decisions:
# - Every column-name reference returns Result[T, FrameError] with a
#   machine-readable code — agents always know exactly what failed.
# - All DataFrames carry a provenance log (List[Op]) so agents can
#   explain the transformation chain that produced a frame.
# - Construction validates length invariants eagerly.
# - Storage is column-oriented for efficient column-level aggregations.

import "std.list" as list
import "std.map"  as map
import "std.str"  as str
import "std.int"  as int
import "./value"      as val
import "./provenance" as prov

type DataFrame = {
  col_names  :: List[Str],
  columns    :: Map[Str, List[Value]],
  nrows      :: Int,
  provenance :: List[prov.Op],
}

# Structured error — machine-readable code + human message + context hint.
type FrameError = {
  code    :: Str,
  message :: Str,
  context :: Str,
}

fn frame_error(code :: Str, message :: Str, context :: Str) -> FrameError {
  { code: code, message: message, context: context }
}

fn not_found_error(col :: Str) -> FrameError {
  frame_error(
    "column_not_found",
    str.concat("column does not exist: ", col),
    "call col_names(df) to list available columns")
}

fn length_mismatch_error(expected :: Int, got :: Int) -> FrameError {
  frame_error(
    "length_mismatch",
    str.concat("expected ", str.concat(int.to_str(expected), str.concat(" rows, got ", int.to_str(got)))),
    "all columns in a DataFrame must have the same row count")
}

fn duplicate_col_error(col :: Str) -> FrameError {
  frame_error(
    "duplicate_column",
    str.concat("column already exists: ", col),
    "use rename or drop before adding a column with the same name")
}

fn format_error(e :: FrameError) -> Str {
  str.concat("[", str.concat(e.code, str.concat("] ", str.concat(e.message, str.concat(" — ", e.context)))))
}

# ---- Construction -------------------------------------------------

fn empty() -> DataFrame {
  { col_names: [], columns: map.new(), nrows: 0, provenance: [] }
}

fn from_columns(cols :: List[(Str, List[Value])]) -> Result[DataFrame, FrameError] {
  if list.is_empty(cols) { Ok(empty()) }
  else {
    let first_len := col_pair_len(list.head(cols))
    let bad := list.find(cols, fn (p :: (Str, List[Value])) -> Bool {
      list.len(col_pair_vals(p)) != first_len
    })
    match bad {
      Some(p) => Err(length_mismatch_error(first_len, list.len(col_pair_vals(p)))),
      None    => {
        let names := list.map(cols, fn (p :: (Str, List[Value])) -> Str { col_pair_name(p) })
        let cols_map := list.fold(cols, map.new(),
          fn (m :: Map[Str, List[Value]], p :: (Str, List[Value])) -> Map[Str, List[Value]] {
            map.set(m, col_pair_name(p), col_pair_vals(p))
          })
        let df := { col_names: names, columns: cols_map, nrows: first_len, provenance: [] }
        Ok(record_op(df, prov.op_load("from_columns", first_len)))
      },
    }
  }
}

# ---- Pair helpers ------------------------------------------------

fn col_pair_name(p :: (Str, List[Value]))   -> Str        { match p { (k, _) => k } }
fn col_pair_vals(p :: (Str, List[Value]))   -> List[Value] { match p { (_, v) => v } }
fn col_pair_len(opt :: Option[(Str, List[Value])]) -> Int {
  match opt { None => 0, Some(p) => list.len(col_pair_vals(p)) }
}

# ---- Query -------------------------------------------------------

fn n_rows(df :: DataFrame)    -> Int       { df.nrows }
fn n_cols(df :: DataFrame)    -> Int       { list.len(df.col_names) }
fn col_names(df :: DataFrame) -> List[Str] { df.col_names }

fn has_column(df :: DataFrame, name :: Str) -> Bool {
  list.any(df.col_names, fn (n :: Str) -> Bool { n == name })
}

fn get_column(df :: DataFrame, name :: Str) -> Option[List[Value]] {
  map.get(df.columns, name)
}

fn require_column(df :: DataFrame, name :: Str) -> Result[List[Value], FrameError] {
  match map.get(df.columns, name) {
    Some(col) => Ok(col),
    None      => Err(not_found_error(name)),
  }
}

# Row as ordered (name, value) pairs — the natural format for agents.
fn get_row(df :: DataFrame, idx :: Int) -> Option[List[(Str, Value)]] {
  if idx < 0 or idx >= df.nrows { None }
  else {
    Some(list.map(df.col_names, fn (name :: Str) -> (Str, Value) {
      let v := match map.get(df.columns, name) {
        None      => val.VNull,
        Some(col) => nth_value(col, idx),
      }
      (name, v)
    }))
  }
}

# Pick value at position idx. Returns VNull for out-of-bounds.
# Uses a (Bool, Value) accumulator to distinguish "not found" from VNull cell.
fn nth_value(col :: List[Value], idx :: Int) -> Value {
  let result := list.fold(list.enumerate(col), (false, val.VNull),
    fn (acc :: (Bool, Value), p :: (Int, Value)) -> (Bool, Value) {
      let found := match acc { (f, _) => f }
      if found { acc }
      else {
        let i := match p { (a, _) => a }
        let v := match p { (_, b) => b }
        if i == idx { (true, v) } else { (false, val.VNull) }
      }
    })
  match result { (_, v) => v }
}

# ---- Row selection -----------------------------------------------

fn pick_rows(df :: DataFrame, indices :: List[Int]) -> DataFrame {
  let new_cols := list.fold(df.col_names, map.new(),
    fn (m :: Map[Str, List[Value]], name :: Str) -> Map[Str, List[Value]] {
      match map.get(df.columns, name) {
        None      => m,
        Some(col) => map.set(m, name, pick_by_indices(col, indices)),
      }
    })
  { col_names: df.col_names, columns: new_cols, nrows: list.len(indices), provenance: df.provenance }
}

fn pick_by_indices(col :: List[Value], indices :: List[Int]) -> List[Value] {
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Value], i :: Int) -> List[Value] {
      list.cons(nth_value(col, i), acc)
    }))
}

fn head(df :: DataFrame, n :: Int) -> DataFrame {
  let actual := int.min(n, df.nrows)
  let sub    := pick_rows(df, range_list(0, actual))
  record_op(sub, prov.op_head(actual))
}

fn tail(df :: DataFrame, n :: Int) -> DataFrame {
  let actual := int.min(n, df.nrows)
  let start  := df.nrows - actual
  let sub    := pick_rows(df, range_list(start, df.nrows))
  record_op(sub, prov.op_tail(actual))
}

fn slice_rows(df :: DataFrame, from :: Int, to :: Int) -> DataFrame {
  let f  := int.max(0, from)
  let t  := int.min(to, df.nrows)
  let sub := pick_rows(df, range_list(f, t))
  record_op(sub, prov.op_slice(f, t))
}

# ---- Column mutation (immutable — returns new DataFrame) ----------

fn add_column(df :: DataFrame, name :: Str, col :: List[Value]) -> Result[DataFrame, FrameError] {
  if has_column(df, name) { Err(duplicate_col_error(name)) }
  else if df.nrows != 0 and list.len(col) != df.nrows { Err(length_mismatch_error(df.nrows, list.len(col))) }
  else {
    let new_nrows := if df.nrows == 0 { list.len(col) } else { df.nrows }
    let new_df := {
      col_names:  list.concat(df.col_names, [name]),
      columns:    map.set(df.columns, name, col),
      nrows:      new_nrows,
      provenance: df.provenance,
    }
    Ok(record_op(new_df, prov.op_add_col(name, "literal")))
  }
}

fn drop_column(df :: DataFrame, name :: Str) -> DataFrame {
  let new_names := list.filter(df.col_names, fn (n :: Str) -> Bool { n != name })
  let new_cols  := list.fold(new_names, map.new(),
    fn (m :: Map[Str, List[Value]], n :: Str) -> Map[Str, List[Value]] {
      match map.get(df.columns, n) {
        None      => m,
        Some(col) => map.set(m, n, col),
      }
    })
  let new_df := { col_names: new_names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
  record_op(new_df, prov.op_drop([name]))
}

# ---- Provenance helpers ------------------------------------------

fn record_op(df :: DataFrame, op :: prov.Op) -> DataFrame {
  { col_names: df.col_names, columns: df.columns, nrows: df.nrows,
    provenance: list.concat(df.provenance, [op]) }
}

# Named-pipe combinator: apply a transform and record it by name.
# Lets agents build readable chains: pipe(df, "normalize", normalize_fn)
fn pipe(df :: DataFrame, name :: Str, transform :: (DataFrame) -> DataFrame) -> DataFrame {
  let result := transform(df)
  record_op(result, prov.op_pipe(name))
}

# ---- Numeric helpers ---------------------------------------------

fn range_list(from :: Int, to :: Int) -> List[Int] {
  list.reverse(range_acc(from, to, []))
}

fn range_acc(i :: Int, to :: Int, acc :: List[Int]) -> List[Int] {
  if i >= to { acc } else { range_acc(i + 1, to, list.cons(i, acc)) }
}
