# lex-frame — sort operations
#
# Builds a sort index over the key column (as Values for comparison),
# then reorders all columns using col.col_pick.

import "std.list" as list
import "std.map"  as map
import "./value"      as val
import "./col"        as col
import "./frame"      as frame
import "./provenance" as prov

fn sort_by(df :: frame.DataFrame, col_name :: Str, asc :: Bool) -> frame.DataFrame {
  match map.get(df.columns, col_name) {
    None    => df,
    Some(c) => {
      let key_vals := col.col_to_values(c)
      let indexed  := list.enumerate(key_vals)
      let sorted   := merge_sort(indexed, asc)
      let indices  := list.map(sorted, fn (p :: (Int, val.Value)) -> Int { match p { (i, _) => i } })
      let sub      := frame.pick_rows(df, indices)
      frame.record_op(sub, prov.op_sort(col_name, asc))
    },
  }
}

fn sort_by_cols(df :: frame.DataFrame, specs :: List[(Str, Bool)]) -> frame.DataFrame {
  list.fold(list.reverse(specs), df, fn (acc :: frame.DataFrame, spec :: (Str, Bool)) -> frame.DataFrame {
    sort_by(acc, match spec { (a, _) => a }, match spec { (_, b) => b })
  })
}

fn merge_sort(xs :: List[(Int, val.Value)], asc :: Bool) -> List[(Int, val.Value)] {
  let n := list.len(xs)
  if n <= 1 { xs }
  else {
    let half  := n / 2
    let left  := take_pairs(xs, half)
    let right := drop_pairs(xs, half)
    merge_pairs(merge_sort(left, asc), merge_sort(right, asc), asc)
  }
}

fn merge_pairs(a :: List[(Int, val.Value)], b :: List[(Int, val.Value)], asc :: Bool) -> List[(Int, val.Value)] {
  match (list.head(a), list.head(b)) {
    (None, _)       => b,
    (_, None)       => a,
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

fn take_pairs(xs :: List[(Int, val.Value)], n :: Int) -> List[(Int, val.Value)] {
  list.reverse(list.fold(list.enumerate(xs), [],
    fn (acc :: List[(Int, val.Value)], p :: (Int, (Int, val.Value))) -> List[(Int, val.Value)] {
      let i  := match p { (a, _) => a }
      let kv := match p { (_, b) => b }
      if i < n { list.cons(kv, acc) } else { acc }
    }))
}

fn drop_pairs(xs :: List[(Int, val.Value)], n :: Int) -> List[(Int, val.Value)] {
  list.reverse(list.fold(list.enumerate(xs), [],
    fn (acc :: List[(Int, val.Value)], p :: (Int, (Int, val.Value))) -> List[(Int, val.Value)] {
      let i  := match p { (a, _) => a }
      let kv := match p { (_, b) => b }
      if i >= n { list.cons(kv, acc) } else { acc }
    }))
}
