import "std.list" as list

import "std.int" as int

import "std.float" as float

import "std.math" as math

import "std.map" as map

import "./value" as val

import "./frame" as frame

fn get_col(df :: frame.DataFrame, name :: Str) -> List[val.Value] {
  match map.get(df.columns, name) {
    Some(c) => c,
    None => [],
  }
}

fn non_null(col :: List[val.Value]) -> List[val.Value] {
  list.filter(col, fn (v :: val.Value) -> Bool {
    if val.is_null(v) {
      false
    } else {
      true
    }
  })
}

fn numeric_floats(col :: List[val.Value]) -> List[Float] {
  list.fold(non_null(col), [], fn (acc :: List[Float], v :: val.Value) -> List[Float] {
    match val.as_float(v) {
      Some(f) => list.cons(f, acc),
      None => acc,
    }
  })
}

fn all_ints(col :: List[val.Value]) -> Bool {
  list.fold(col, true, fn (acc :: Bool, v :: val.Value) -> Bool {
    acc and (val.is_null(v) or match val.as_int(v) {
      Some(_) => true,
      None => false,
    })
  })
}

fn count_all(df :: frame.DataFrame, _col :: Str) -> Int {
  df.nrows
}

fn count_non_null(df :: frame.DataFrame, col_name :: Str) -> Int {
  list.len(non_null(get_col(df, col_name)))
}

fn sum_col(df :: frame.DataFrame, col_name :: Str) -> Option[val.Value] {
  let col := get_col(df, col_name)
  let nn := non_null(col)
  if list.is_empty(nn) {
    None
  } else {
    if all_ints(col) {
      let total := list.fold(nn, 0, fn (acc :: Int, v :: val.Value) -> Int {
        match val.as_int(v) {
          Some(n) => acc + n,
          None => acc,
        }
      })
      Some(val.vint(total))
    } else {
      let total := list.fold(nn, 0.0, fn (acc :: Float, v :: val.Value) -> Float {
        match val.as_float(v) {
          Some(f) => acc + f,
          None => acc,
        }
      })
      Some(val.vfloat(total))
    }
  }
}

fn mean_col(df :: frame.DataFrame, col_name :: Str) -> Option[Float] {
  let nums := numeric_floats(get_col(df, col_name))
  let n := list.len(nums)
  if n == 0 {
    None
  } else {
    let total := list.fold(nums, 0.0, fn (acc :: Float, f :: Float) -> Float {
      acc + f
    })
    Some(total / int.to_float(n))
  }
}

fn min_col(df :: frame.DataFrame, col_name :: Str) -> Option[val.Value] {
  let col := non_null(get_col(df, col_name))
  match list.head(col) {
    None => None,
    Some(h) => Some(list.fold(col, h, fn (acc :: val.Value, v :: val.Value) -> val.Value {
      if val.lt(v, acc) {
        v
      } else {
        acc
      }
    })),
  }
}

fn max_col(df :: frame.DataFrame, col_name :: Str) -> Option[val.Value] {
  let col := non_null(get_col(df, col_name))
  match list.head(col) {
    None => None,
    Some(h) => Some(list.fold(col, h, fn (acc :: val.Value, v :: val.Value) -> val.Value {
      if val.gt(v, acc) {
        v
      } else {
        acc
      }
    })),
  }
}

fn variance_col(df :: frame.DataFrame, col_name :: Str) -> Option[Float] {
  let nums := numeric_floats(get_col(df, col_name))
  let n := list.len(nums)
  if n < 2 {
    None
  } else {
    let n_f := int.to_float(n)
    let total := list.fold(nums, 0.0, fn (acc :: Float, f :: Float) -> Float {
      acc + f
    })
    let mean := total / n_f
    let sq := list.fold(nums, 0.0, fn (acc :: Float, f :: Float) -> Float {
      let d := f - mean
      acc + d * d
    })
    Some(sq / int.to_float(n - 1))
  }
}

fn std_col(df :: frame.DataFrame, col_name :: Str) -> Option[Float] {
  match variance_col(df, col_name) {
    None => None,
    Some(v) => Some(math.sqrt(v)),
  }
}

fn n_distinct(df :: frame.DataFrame, col_name :: Str) -> Int {
  let seen := list.fold(get_col(df, col_name), map.new(), fn (acc :: Map[Str, Bool], v :: val.Value) -> Map[Str, Bool] {
    map.set(acc, val.to_str(v), true)
  })
  map.fold(seen, 0, fn (acc :: Int, _k :: Str, _v :: Bool) -> Int {
    acc + 1
  })
}

fn dedup_vals(col :: List[val.Value]) -> List[val.Value] {
  let res := list.fold(col, (map.new(), []), fn (acc :: (Map[Str, Bool], List[val.Value]), v :: val.Value) -> (Map[Str, Bool], List[val.Value]) {
    match acc {
      (seen, out) => {
        let key := val.to_str(v)
        match map.get(seen, key) {
          Some(_) => (seen, out),
          None => (map.set(seen, key, true), list.cons(v, out)),
        }
      },
    }
  })
  match res {
    (_, out) => list.reverse(out),
  }
}

