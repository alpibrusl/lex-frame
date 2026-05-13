# lex-frame — column-level aggregation functions
#
# All functions take a List[Value] (a column) and return a scalar.
# Non-numeric values are silently skipped in numeric aggregations.
# Null values are always excluded from counts unless using count_all.

import "std.list"  as list
import "std.int"   as int
import "std.float" as float
import "std.math"  as math
import "./value" as val

# Total row count (including nulls).
fn count_all(col :: List[Value]) -> Int { list.len(col) }

# Count of non-null values.
fn count_non_null(col :: List[Value]) -> Int {
  list.fold(col, 0, fn (acc :: Int, v :: Value) -> Int {
    if val.is_null(v) { acc } else { acc + 1 }
  })
}

# Sum of numeric values. Returns VNull if no numeric values.
fn sum_col(col :: List[Value]) -> Value {
  let nums := list.filter(col, fn (v :: Value) -> Bool { val.is_numeric(v) })
  if list.is_empty(nums) { val.VNull }
  else {
    # Detect if any Float is present; if so, sum as Float.
    let has_float := list.any(nums, fn (v :: Value) -> Bool {
      match v { VFloat(_) => true, _ => false }
    })
    if has_float {
      let total := list.fold(nums, 0.0, fn (acc :: Float, v :: Value) -> Float {
        match val.as_float(v) { Some(x) => acc + x, None => acc }
      })
      val.VFloat(total)
    } else {
      let total := list.fold(nums, 0, fn (acc :: Int, v :: Value) -> Int {
        match val.as_int(v) { Some(n) => acc + n, None => acc }
      })
      val.VInt(total)
    }
  }
}

# Mean of numeric values. Always returns Float.
fn mean_col(col :: List[Value]) -> Option[Float] {
  let nums := list.filter(col, fn (v :: Value) -> Bool { val.is_numeric(v) })
  let n    := list.len(nums)
  if n == 0 { None }
  else {
    let total := list.fold(nums, 0.0, fn (acc :: Float, v :: Value) -> Float {
      match val.as_float(v) { Some(x) => acc + x, None => acc }
    })
    Some(total / int.to_float(n))
  }
}

# Minimum value (excluding nulls). Uses val.lt for ordering.
fn min_col(col :: List[Value]) -> Option[Value] {
  let non_null := list.filter(col, fn (v :: Value) -> Bool { not val.is_null(v) })
  match list.head(non_null) {
    None    => None,
    Some(h) => Some(list.fold(non_null, h, fn (acc :: Value, v :: Value) -> Value {
      if val.lt(v, acc) { v } else { acc }
    })),
  }
}

# Maximum value (excluding nulls).
fn max_col(col :: List[Value]) -> Option[Value] {
  let non_null := list.filter(col, fn (v :: Value) -> Bool { not val.is_null(v) })
  match list.head(non_null) {
    None    => None,
    Some(h) => Some(list.fold(non_null, h, fn (acc :: Value, v :: Value) -> Value {
      if val.gt(v, acc) { v } else { acc }
    })),
  }
}

# Variance (population) of numeric values.
fn variance_col(col :: List[Value]) -> Option[Float] {
  match mean_col(col) {
    None    => None,
    Some(m) => {
      let nums := list.filter(col, fn (v :: Value) -> Bool { val.is_numeric(v) })
      let n    := list.len(nums)
      if n == 0 { None }
      else {
        let sq_sum := list.fold(nums, 0.0, fn (acc :: Float, v :: Value) -> Float {
          match val.as_float(v) {
            None    => acc,
            Some(x) => { let d := x - m
                          acc + d * d },
          }
        })
        Some(sq_sum / int.to_float(n))
      }
    },
  }
}

# Standard deviation (population).
fn std_col(col :: List[Value]) -> Option[Float] {
  match variance_col(col) {
    None    => None,
    Some(v) => Some(math.sqrt(v)),
  }
}

# Count distinct non-null values.
fn n_distinct(col :: List[Value]) -> Int {
  let non_null := list.filter(col, fn (v :: Value) -> Bool { not val.is_null(v) })
  list.len(dedup_vals(non_null))
}

# Remove duplicate Values preserving first-occurrence order.
fn dedup_vals(xs :: List[Value]) -> List[Value] {
  list.reverse(list.fold(xs, [],
    fn (acc :: List[Value], v :: Value) -> List[Value] {
      let already := list.any(acc, fn (a :: Value) -> Bool { val.eq(a, v) })
      if already { acc } else { list.cons(v, acc) }
    }))
}
