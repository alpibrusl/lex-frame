# lex-frame — join operations
#
# inner_join: keep rows where the key exists in both frames.
# left_join:  keep all left rows; right columns are VNull on no match.
# cross_join: cartesian product (use with caution on large frames).
#
# Duplicate column names (other than the join key) are disambiguated
# with "_left" / "_right" suffixes so agents always get a valid frame.

import "std.list" as list
import "std.map"  as map
import "std.str"  as str
import "std.int"  as int
import "./value"      as val
import "./frame"      as frame
import "./provenance" as prov

# ---- Public API ---------------------------------------------------

fn inner_join(
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  on    :: Str
) -> Result[frame.DataFrame, frame.FrameError] {
  match check_join_cols(left, right, on) {
    Err(e) => Err(e),
    Ok(()) => {
      let right_index := build_index(right, on)
      let result_cols := init_result_cols(left, right, on)
      let right_key_col := match map.get(right.columns, on) { Some(c) => c, None => [] }
      let filled := list.fold(frame.range_list(0, left.nrows), result_cols,
        fn (acc :: List[(Str, List[Value])], i :: Int) -> List[(Str, List[Value])] {
          let lk := frame.nth_value(match map.get(left.columns, on) { Some(c) => c, None => [] }, i)
          let matches := find_matches(right_index, right_key_col, lk)
          list.fold(matches, acc, fn (acc2 :: List[(Str, List[Value])], ri :: Int) -> List[(Str, List[Value])] {
            append_row_pair(acc2, left, right, i, ri, on)
          })
        })
      build_result(filled, left, right, on, "inner")
    },
  }
}

fn left_join(
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  on    :: Str
) -> Result[frame.DataFrame, frame.FrameError] {
  match check_join_cols(left, right, on) {
    Err(e) => Err(e),
    Ok(()) => {
      let right_index   := build_index(right, on)
      let right_key_col := match map.get(right.columns, on) { Some(c) => c, None => [] }
      let result_cols   := init_result_cols(left, right, on)
      let filled := list.fold(frame.range_list(0, left.nrows), result_cols,
        fn (acc :: List[(Str, List[Value])], i :: Int) -> List[(Str, List[Value])] {
          let lk      := frame.nth_value(match map.get(left.columns, on) { Some(c) => c, None => [] }, i)
          let matches := find_matches(right_index, right_key_col, lk)
          if list.is_empty(matches) {
            append_row_null_right(acc, left, right, i, on)
          } else {
            list.fold(matches, acc, fn (acc2 :: List[(Str, List[Value])], ri :: Int) -> List[(Str, List[Value])] {
              append_row_pair(acc2, left, right, i, ri, on)
            })
          }
        })
      build_result(filled, left, right, on, "left")
    },
  }
}

fn cross_join(left :: frame.DataFrame, right :: frame.DataFrame) -> frame.DataFrame {
  let left_names  := left.col_names
  let right_names := list.filter(right.col_names, fn (n :: Str) -> Bool {
    not list.any(left_names, fn (ln :: Str) -> Bool { ln == n })
  })
  let init := list.map(list.concat(left_names, right_names),
    fn (n :: Str) -> (Str, List[Value]) { (n, []) })
  let filled := list.fold(frame.range_list(0, left.nrows), init,
    fn (acc :: List[(Str, List[Value])], li :: Int) -> List[(Str, List[Value])] {
      list.fold(frame.range_list(0, right.nrows), acc,
        fn (acc2 :: List[(Str, List[Value])], ri :: Int) -> List[(Str, List[Value])] {
          append_row_pair(acc2, left, right, li, ri, "")
        })
    })
  let n := left.nrows * right.nrows
  let all_names := list.concat(left_names, right_names)
  let cols_map  := list.fold(list.zip(all_names, list.map(filled, fn (p :: (Str, List[Value])) -> List[Value] { match p { (_, v) => v } })),
    map.new(), fn (m :: Map[Str, List[Value]], p :: (Str, List[Value])) -> Map[Str, List[Value]] {
      map.set(m, match p { (k, _) => k }, match p { (_, v) => v })
    })
  frame.record_op(
    { col_names: all_names, columns: cols_map, nrows: n, provenance: left.provenance },
    prov.op_join("cross", "cross", n))
}

# ---- Internal helpers --------------------------------------------

fn check_join_cols(
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  on    :: Str
) -> Result[Unit, frame.FrameError] {
  if not frame.has_column(left, on)  { Err(frame.not_found_error(str.concat("left.", on))) }
  else if not frame.has_column(right, on) { Err(frame.not_found_error(str.concat("right.", on))) }
  else { Ok(()) }
}

# Build Map[Str, List[Int]]: key_str → right row indices.
fn build_index(df :: frame.DataFrame, col :: Str) -> Map[Str, List[Int]] {
  match map.get(df.columns, col) {
    None     => map.new(),
    Some(xs) =>
      list.fold(list.enumerate(xs), map.new(),
        fn (m :: Map[Str, List[Int]], p :: (Int, Value)) -> Map[Str, List[Int]] {
          let i := match p { (a, _) => a }
          let v := match p { (_, b) => b }
          let k := val.to_str(v)
          let existing := match map.get(m, k) { Some(js) => js, None => [] }
          map.set(m, k, list.concat(existing, [i]))
        }),
  }
}

fn find_matches(index :: Map[Str, List[Int]], _right_col :: List[Value], key :: Value) -> List[Int] {
  match map.get(index, val.to_str(key)) { Some(is) => is, None => [] }
}

# Column list for the result: on + disambiguated columns from left + right.
fn result_col_names(left :: frame.DataFrame, right :: frame.DataFrame, on :: Str) -> List[Str] {
  let left_rest  := list.filter(left.col_names,  fn (n :: Str) -> Bool { n != on })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool { n != on })
  let right_dis  := list.map(right_rest, fn (n :: Str) -> Str {
    if list.any(left_rest, fn (ln :: Str) -> Bool { ln == n }) {
      str.concat(n, "_right")
    } else { n }
  })
  list.concat([on], list.concat(left_rest, right_dis))
}

fn init_result_cols(
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  on    :: Str
) -> List[(Str, List[Value])] {
  list.map(result_col_names(left, right, on), fn (n :: Str) -> (Str, List[Value]) { (n, []) })
}

fn append_row_pair(
  acc   :: List[(Str, List[Value])],
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  li    :: Int,
  ri    :: Int,
  on    :: Str
) -> List[(Str, List[Value])] {
  let left_rest  := list.filter(left.col_names,  fn (n :: Str) -> Bool { n != on })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool { n != on })
  let on_val     := frame.nth_value(match map.get(left.columns, on) { Some(c) => c, None => [] }, li)
  let row_vals := list.concat([on_val],
    list.concat(
      list.map(left_rest,  fn (n :: Str) -> Value { frame.nth_value(match map.get(left.columns,  n) { Some(c) => c, None => [] }, li) }),
      list.map(right_rest, fn (n :: Str) -> Value { frame.nth_value(match map.get(right.columns, n) { Some(c) => c, None => [] }, ri) })
    ))
  list.map(list.zip(acc, row_vals),
    fn (p :: ((Str, List[Value]), Value)) -> (Str, List[Value]) {
      let col_pair := match p { (a, _) => a }
      let v        := match p { (_, b) => b }
      let name     := match col_pair { (k, _) => k }
      let existing := match col_pair { (_, vs) => vs }
      (name, list.concat(existing, [v]))
    })
}

fn append_row_null_right(
  acc   :: List[(Str, List[Value])],
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  li    :: Int,
  on    :: Str
) -> List[(Str, List[Value])] {
  let left_rest  := list.filter(left.col_names,  fn (n :: Str) -> Bool { n != on })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool { n != on })
  let on_val    := frame.nth_value(match map.get(left.columns, on) { Some(c) => c, None => [] }, li)
  let row_vals  := list.concat([on_val],
    list.concat(
      list.map(left_rest,  fn (n :: Str) -> Value { frame.nth_value(match map.get(left.columns, n) { Some(c) => c, None => [] }, li) }),
      list.map(right_rest, fn (_n :: Str) -> Value { val.VNull })
    ))
  list.map(list.zip(acc, row_vals),
    fn (p :: ((Str, List[Value]), Value)) -> (Str, List[Value]) {
      let col_pair := match p { (a, _) => a }
      let v        := match p { (_, b) => b }
      (match col_pair { (k, _) => k }, list.concat(match col_pair { (_, vs) => vs }, [v]))
    })
}

fn build_result(
  filled :: List[(Str, List[Value])],
  left   :: frame.DataFrame,
  right  :: frame.DataFrame,
  on     :: Str,
  kind   :: Str
) -> Result[frame.DataFrame, frame.FrameError] {
  match frame.from_columns(filled) {
    Err(e)  => Err(e),
    Ok(df)  => Ok(frame.record_op(df, prov.op_join(on, kind, df.nrows))),
  }
}
