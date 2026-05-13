# lex-frame — sort operations
#
# sort_by: sort all rows by one column’s values (asc or desc).
# sort_by_cols: multi-key sort (primary, secondary, ...).
#
# Internally: argsort via merge sort on List[(Int, Value)] to get
# a sorted permutation of row indices, then reorder all columns.
# merge_sort is O(n log n). No stdlib sort required.

import "std.list" as list
import "std.str"  as str
import "./value"      as val
import "./frame"      as frame
import "./provenance" as prov

# Sort the DataFrame by column `col`. Returns Err if col not found.
fn sort_by(
  df  :: frame.DataFrame,
  col :: Str,
  asc :: Bool
) -> Result[frame.DataFrame, frame.FrameError] {
  match map.get(df.columns, col) {
    None          => Err(frame.not_found_error(col)),
    Some(key_col) => {
      let indexed      := list.enumerate(key_col)
      let sorted_pairs := merge_sort(indexed, asc)
      let indices      := list.map(sorted_pairs, fn (p :: (Int, Value)) -> Int { match p { (i, _) => i } })
      let sub          := frame.pick_rows(df, indices)
      Ok(frame.record_op(sub, prov.op_sort(col, asc)))
    },
  }
}

# Multi-key sort: specs is List[(col, ascending)].
# Sorts by the first key, breaking ties with subsequent keys.
fn sort_by_cols(
  df    :: frame.DataFrame,
  specs :: List[(Str, Bool)]
) -> Result[frame.DataFrame, frame.FrameError] {
  list.fold(list.reverse(specs), Ok(df),
    fn (acc :: Result[frame.DataFrame, frame.FrameError], spec :: (Str, Bool)) -> Result[frame.DataFrame, frame.FrameError] {
      match acc {
        Err(e) => Err(e),
        Ok(d)  => {
          let col := match spec { (a, _) => a }
          let asc := match spec { (_, b) => b }
          sort_by(d, col, asc)
        },
      }
    })
}

# ---- Merge sort on List[(Int, Value)] ----------------------------

import "std.map" as map

fn merge_sort(xs :: List[(Int, Value)], asc :: Bool) -> List[(Int, Value)] {
  let n := list.len(xs)
  if n <= 1 { xs }
  else {
    let half  := n / 2
    let left  := take_pairs(xs, half)
    let right := drop_pairs(xs, half)
    merge_pairs(merge_sort(left, asc), merge_sort(right, asc), asc)
  }
}

fn merge_pairs(
  a   :: List[(Int, Value)],
  b   :: List[(Int, Value)],
  asc :: Bool
) -> List[(Int, Value)] {
  match (list.head(a), list.head(b)) {
    (None, _)            => b,
    (_, None)            => a,
    (Some(pa), Some(pb)) => {
      let va     := match pa { (_, v) => v }
      let vb     := match pb { (_, v) => v }
      let take_a := if asc { val.lte(va, vb) } else { val.gte(va, vb) }
      if take_a {
        list.cons(pa, merge_pairs(list.tail(a), b, asc))
      } else {
        list.cons(pb, merge_pairs(a, list.tail(b), asc))
      }
    },
  }
}

fn take_pairs(xs :: List[(Int, Value)], n :: Int) -> List[(Int, Value)] {
  list.reverse(list.fold(list.enumerate(xs), [],
    fn (acc :: List[(Int, Value)], p :: (Int, (Int, Value))) -> List[(Int, Value)] {
      let i  := match p { (a, _) => a }
      let kv := match p { (_, b) => b }
      if i < n { list.cons(kv, acc) } else { acc }
    }))
}

fn drop_pairs(xs :: List[(Int, Value)], n :: Int) -> List[(Int, Value)] {
  list.reverse(list.fold(list.enumerate(xs), [],
    fn (acc :: List[(Int, Value)], p :: (Int, (Int, Value))) -> List[(Int, Value)] {
      let i  := match p { (a, _) => a }
      let kv := match p { (_, b) => b }
      if i >= n { list.cons(kv, acc) } else { acc }
    }))
}
