# Column-level aggregation functions.
# All aggregations skip VNull values unless stated otherwise.

import "std.list"  as list
import "std.int"   as int
import "std.float" as float
import "std.math"  as math
import "std.map"   as map
import "./value" as val
import "./frame" as frame

fn get_col(df :: frame.DataFrame, name :: Str) -> List[val.Value] {
  match map.get(df.columns, name) { Some(c) => c, None => [] }
}

fn count_all(df :: frame.DataFrame, col :: Str) -> Int {
  df.nrows
}

fn count_non_null(df :: frame.DataFrame, col :: Str) -> Int {
  list.len(list.filter(get_col(df, col), fn (v :: val.Value) -> Bool {
    if val.is_null(v) { false } else { true }
  }))
}

fn numeric_vals(col :: List[val.Value]) -> List[Float] {
  list.fold(col, [], fn (acc :: List[Float], v :: val.Value) -> List[Float] {
    match val.as_float(v) {
      Some(f) => list.cons(f, acc),
      None    => acc,
    }
  })
}

fn all_ints(col :: List[val.Value]) -> Bool {
  list.all(col, fn (v :: val.Value) -> Bool {
    match v { val.VInt(_) => true, val.VNull => true, _ => false }
  })
}

fn sum_col(df :: frame.DataFrame, col_name :: Str) -> Option[val.Value] {
  let col := get_col(df, col_name)
  let nums := numeric_vals(col)
  if list.is_empty(nums) { None }
  else {
    let total := list.fold(nums, 0.0, fn (acc :: Float, f :: Float) -> Float { acc + f })
    if all_ints(col) {
      match int.parse(float.to_str(total)) {
        Some(n) => Some(val.VInt(n)),
        None    => Some(val.VFloat(total)),
      }
    } else {
      Some(val.VFloat(total))
    }
  }
}

fn mean_col(df :: frame.DataFrame, col_name :: Str) -> Option[Float] {
  let nums := numeric_vals(get_col(df, col_name))
  let n := list.len(nums)
  if n == 0 { None }
  else {
    let total := list.fold(nums, 0.0, fn (acc :: Float, f :: Float) -> Float { acc + f })
    Some(total / int.to_float(n))
  }
}

fn min_col(df :: frame.DataFrame, col_name :: Str) -> Option[val.Value] {
  let col := list.filter(get_col(df, col_name), fn (v :: val.Value) -> Bool {
    if val.is_null(v) { false } else { true }
  })
  if list.is_empty(col) { None }
  else {
    match list.head(col) {
      None    => None,
      Some(h) => Some(list.fold(col, h, fn (acc :: val.Value, v :: val.Value) -> val.Value {
        if val.lt(v, acc) { v } else { acc }
      }))
    }
  }
}

fn max_col(df :: frame.DataFrame, col_name :: Str) -> Option[val.Value] {
  let col := list.filter(get_col(df, col_name), fn (v :: val.Value) -> Bool {
    if val.is_null(v) { false } else { true }
  })
  if list.is_empty(col) { None }
  else {
    match list.head(col) {
      None    => None,
      Some(h) => Some(list.fold(col, h, fn (acc :: val.Value, v :: val.Value) -> val.Value {
        if val.gt(v, acc) { v } else { acc }
      }))
    }
  }
}

fn variance_col(df :: frame.DataFrame, col_name :: Str) -> Option[Float] {
  let nums := numeric_vals(get_col(df, col_name))
  let n := list.len(nums)
  if n < 2 { None }
  else {
    let n_f := int.to_float(n)
    let sum := list.fold(nums, 0.0, fn (acc :: Float, f :: Float) -> Float { acc + f })
    let mean := sum / n_f
    let sq_diff := list.fold(nums, 0.0, fn (acc :: Float, f :: Float) -> Float {
      let d := f - mean
      acc + d * d
    })
    Some(sq_diff / int.to_float(n - 1))
  }
}

fn std_col(df :: frame.DataFrame, col_name :: Str) -> Option[Float] {
  match variance_col(df, col_name) {
    None    => None,
    Some(v) => Some(math.sqrt(v)),
  }
}

fn n_distinct(df :: frame.DataFrame, col_name :: Str) -> Int {
  let col := get_col(df, col_name)
  let seen := list.fold(col, map.new(), fn (acc :: Map[Str, Bool], v :: val.Value) -> Map[Str, Bool] {
    map.set(acc, val.to_str(v), true)
  })
  map.fold(seen, 0, fn (acc :: Int, _k :: Str, _v :: Bool) -> Int { acc + 1 })
}

fn dedup_vals(col :: List[val.Value]) -> List[val.Value] {
  let result := list.fold(col, (map.new(), []), fn (acc :: (Map[Str, Bool], List[val.Value]), v :: val.Value) -> (Map[Str, Bool], List[val.Value]) {
    match acc {
      (seen, out) => {
        let key := val.to_str(v)
        match map.get(seen, key) {
          Some(_) => (seen, out),
          None    => (map.set(seen, key, true), list.cons(v, out)),
        }
      },
    }
  })
  match result { (_, out) => list.reverse(out) }
}
