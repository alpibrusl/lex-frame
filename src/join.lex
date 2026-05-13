# lex-frame — join operations
#
# inner_join: keep rows where the key exists in both frames.
# left_join:  keep all left rows; right columns are VNull on no match.
# cross_join: cartesian product (use with caution on large frames).
#
# Duplicate column names (other than the join key) are disambiguated
# with "_right" suffix so agents always get a valid frame.

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
  match (map.get(left.columns, on), map.get(right.columns, on)) {
    (None, _) => Err(frame.not_found_error(str.concat("left.", on))),
    (_, None) => Err(frame.not_found_error(str.concat("right.", on))),
    (Some(_), Some(_)) => {
      let right_index   := build_index(right, on)
      let out_names     := result_col_names(left, right, on)
      let empty_map     := init_col_map(out_names)
      let right_key_col := match map.get(right.columns, on) { Some(c) => c, None => [] }
      let filled_rev := list.fold(frame.range_list(0, left.nrows), empty_map,
        fn (acc :: Map[Str, List[val.Value]], li :: Int) -> Map[Str, List[val.Value]] {
          let lk      := frame.nth_value(match map.get(left.columns, on) { Some(c) => c, None => [] }, li)
          let matches := match map.get(right_index, val.to_str(lk)) { Some(is) => is, None => [] }
          list.fold(matches, acc,
            fn (acc2 :: Map[Str, List[val.Value]], ri :: Int) -> Map[Str, List[val.Value]] {
              append_pair(acc2, out_names, left, right, on, li, ri)
            })
        })
      finish(filled_rev, out_names, left, right, on, "inner")
    },
  }
}

fn left_join(
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  on    :: Str
) -> Result[frame.DataFrame, frame.FrameError] {
  match (map.get(left.columns, on), map.get(right.columns, on)) {
    (None, _) => Err(frame.not_found_error(str.concat("left.", on))),
    (_, None) => Err(frame.not_found_error(str.concat("right.", on))),
    (Some(_), Some(_)) => {
      let right_index := build_index(right, on)
      let out_names   := result_col_names(left, right, on)
      let empty_map   := init_col_map(out_names)
      let filled_rev := list.fold(frame.range_list(0, left.nrows), empty_map,
        fn (acc :: Map[Str, List[val.Value]], li :: Int) -> Map[Str, List[val.Value]] {
          let lk      := frame.nth_value(match map.get(left.columns, on) { Some(c) => c, None => [] }, li)
          let matches := match map.get(right_index, val.to_str(lk)) { Some(is) => is, None => [] }
          if list.is_empty(matches) {
            append_null_right(acc, out_names, left, right, on, li)
          } else {
            list.fold(matches, acc,
              fn (acc2 :: Map[Str, List[val.Value]], ri :: Int) -> Map[Str, List[val.Value]] {
                append_pair(acc2, out_names, left, right, on, li, ri)
              })
          }
        })
      finish(filled_rev, out_names, left, right, on, "left")
    },
  }
}

fn cross_join(left :: frame.DataFrame, right :: frame.DataFrame) -> Result[frame.DataFrame, frame.FrameError] {
  let left_names  := left.col_names
  let right_names := list.map(right.col_names, fn (n :: Str) -> Str {
    if list.fold(left_names, false, fn (acc :: Bool, ln :: Str) -> Bool { acc or (ln == n) }) { str.concat(n, "_right") } else { n }
  })
  let all_names_rev := list.fold(right_names,
    list.fold(left_names, [], fn (a :: List[Str], s :: Str) -> List[Str] { list.cons(s, a) }),
    fn (a :: List[Str], s :: Str) -> List[Str] { list.cons(s, a) })
  let all_names := list.reverse(all_names_rev)
  let empty_map := init_col_map(all_names)
  let filled_rev := list.fold(frame.range_list(0, left.nrows), empty_map,
    fn (acc :: Map[Str, List[val.Value]], li :: Int) -> Map[Str, List[val.Value]] {
      list.fold(frame.range_list(0, right.nrows), acc,
        fn (acc2 :: Map[Str, List[val.Value]], ri :: Int) -> Map[Str, List[val.Value]] {
          let left_vals := list.map(left.col_names, fn (n :: Str) -> val.Value {
            frame.nth_value(match map.get(left.columns, n) { Some(c) => c, None => [] }, li)
          })
          let right_vals := list.map(right.col_names, fn (n :: Str) -> val.Value {
            frame.nth_value(match map.get(right.columns, n) { Some(c) => c, None => [] }, ri)
          })
          let row_vals_rev := list.fold(right_vals,
            list.fold(left_vals, [], fn (a :: List[val.Value], v :: val.Value) -> List[val.Value] { list.cons(v, a) }),
            fn (a :: List[val.Value], v :: val.Value) -> List[val.Value] { list.cons(v, a) })
          let row_vals := list.reverse(row_vals_rev)
          push_row(acc2, all_names, row_vals)
        })
    })
  let n := left.nrows * right.nrows
  let final_cols := finalize_cols(all_names, filled_rev)
  match frame.from_columns(final_cols) {
    Ok(df) => Ok(frame.record_op(df, prov.op_join("cross", "cross"))),
    Err(e) => Err(e),
  }
}

# ---- Internal helpers --------------------------------------------

# Build Map[Str, List[Int]]: key_str -> right row indices.
fn build_index(df :: frame.DataFrame, col :: Str) -> Map[Str, List[Int]] {
  match map.get(df.columns, col) {
    None     => map.new(),
    Some(xs) =>
      list.fold(list.enumerate(xs), map.new(),
        fn (m :: Map[Str, List[Int]], p :: (Int, val.Value)) -> Map[Str, List[Int]] {
          let i := match p { (a, _) => a }
          let v := match p { (_, b) => b }
          let k := val.to_str(v)
          let existing := match map.get(m, k) { Some(js) => js, None => [] }
          map.set(m, k, list.cons(i, existing))
        }),
  }
}

# Ordered result column names: on key first, then left non-key cols, then right non-key cols.
# Right cols that duplicate a left col name get "_right" suffix.
fn result_col_names(left :: frame.DataFrame, right :: frame.DataFrame, on :: Str) -> List[Str] {
  let left_rest  := list.filter(left.col_names,  fn (n :: Str) -> Bool { n != on })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool { n != on })
  let right_dis  := list.map(right_rest, fn (n :: Str) -> Str {
    if list.fold(left_rest, false, fn (acc :: Bool, ln :: Str) -> Bool { acc or (ln == n) }) { str.concat(n, "_right") } else { n }
  })
  # Build [on] ++ left_rest ++ right_dis
  let rev := list.fold(right_dis,
    list.fold(left_rest, [on], fn (a :: List[Str], s :: Str) -> List[Str] { list.cons(s, a) }),
    fn (a :: List[Str], s :: Str) -> List[Str] { list.cons(s, a) })
  list.reverse(rev)
}

fn init_col_map(names :: List[Str]) -> Map[Str, List[val.Value]] {
  list.fold(names, map.new(),
    fn (m :: Map[Str, List[val.Value]], n :: Str) -> Map[Str, List[val.Value]] {
      map.set(m, n, [])
    })
}

# Append one value to each column in the accumulator map (building in reverse).
fn push_row(
  m        :: Map[Str, List[val.Value]],
  names    :: List[Str],
  row_vals :: List[val.Value]
) -> Map[Str, List[val.Value]] {
  list.fold(list.enumerate(names), m,
    fn (acc :: Map[Str, List[val.Value]], p :: (Int, Str)) -> Map[Str, List[val.Value]] {
      let i    := match p { (a, _) => a }
      let name := match p { (_, b) => b }
      let v    := frame.nth_value(row_vals, i)
      let existing := match map.get(acc, name) { Some(xs) => xs, None => [] }
      map.set(acc, name, list.cons(v, existing))
    })
}

fn append_pair(
  acc   :: Map[Str, List[val.Value]],
  names :: List[Str],
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  on    :: Str,
  li    :: Int,
  ri    :: Int
) -> Map[Str, List[val.Value]] {
  let left_rest  := list.filter(left.col_names,  fn (n :: Str) -> Bool { n != on })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool { n != on })
  let on_val     := frame.nth_value(match map.get(left.columns, on) { Some(c) => c, None => [] }, li)
  let left_vals  := list.map(left_rest, fn (n :: Str) -> val.Value {
    frame.nth_value(match map.get(left.columns, n) { Some(c) => c, None => [] }, li)
  })
  let right_vals := list.map(right_rest, fn (n :: Str) -> val.Value {
    frame.nth_value(match map.get(right.columns, n) { Some(c) => c, None => [] }, ri)
  })
  let row_vals_rev := list.fold(right_vals,
    list.fold(left_vals, [on_val], fn (a :: List[val.Value], v :: val.Value) -> List[val.Value] { list.cons(v, a) }),
    fn (a :: List[val.Value], v :: val.Value) -> List[val.Value] { list.cons(v, a) })
  let row_vals := list.reverse(row_vals_rev)
  push_row(acc, names, row_vals)
}

fn append_null_right(
  acc   :: Map[Str, List[val.Value]],
  names :: List[Str],
  left  :: frame.DataFrame,
  right :: frame.DataFrame,
  on    :: Str,
  li    :: Int
) -> Map[Str, List[val.Value]] {
  let left_rest  := list.filter(left.col_names,  fn (n :: Str) -> Bool { n != on })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool { n != on })
  let on_val     := frame.nth_value(match map.get(left.columns, on) { Some(c) => c, None => [] }, li)
  let left_vals  := list.map(left_rest, fn (n :: Str) -> val.Value {
    frame.nth_value(match map.get(left.columns, n) { Some(c) => c, None => [] }, li)
  })
  let null_vals  := list.map(right_rest, fn (_n :: Str) -> val.Value { val.VNull })
  let row_vals_rev := list.fold(null_vals,
    list.fold(left_vals, [on_val], fn (a :: List[val.Value], v :: val.Value) -> List[val.Value] { list.cons(v, a) }),
    fn (a :: List[val.Value], v :: val.Value) -> List[val.Value] { list.cons(v, a) })
  let row_vals := list.reverse(row_vals_rev)
  push_row(acc, names, row_vals)
}

fn finalize_cols(
  names    :: List[Str],
  col_map  :: Map[Str, List[val.Value]]
) -> List[(Str, List[val.Value])] {
  list.map(names, fn (name :: Str) -> (Str, List[val.Value]) {
    let col_rev := match map.get(col_map, name) { Some(xs) => xs, None => [] }
    (name, list.reverse(col_rev))
  })
}

fn finish(
  filled :: Map[Str, List[val.Value]],
  names  :: List[Str],
  left   :: frame.DataFrame,
  right  :: frame.DataFrame,
  on     :: Str,
  kind   :: Str
) -> Result[frame.DataFrame, frame.FrameError] {
  let final_cols := finalize_cols(names, filled)
  match frame.from_columns(final_cols) {
    Err(e)  => Err(e),
    Ok(df)  => Ok(frame.record_op(df, prov.op_join(kind, on))),
  }
}
