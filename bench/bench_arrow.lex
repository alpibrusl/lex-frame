# Same workload as bench/bench.lex, but the column reductions go through
# std.arrow (lex-lang #426 slice 1) instead of agg.sum_col / agg.mean_col.
#
# Build is still List[Value] (the lex-frame migration in lex-frame#6
# rewires from_columns to land directly into Arrow); only the reductions
# are routed through the new kernels here. This isolates the kernel win.
#
# Sum / mean still walk the build path; arrow_sum / arrow_mean show what
# the kernel itself contributes once we eliminate the construction cost.

import "std.list" as list
import "std.int" as int
import "std.arrow" as arrow

# [1, 2, ..., n] via prepend.
fn ints_loop(i :: Int, acc :: List[Int]) -> List[Int] {
  if i == 0 { acc } else { ints_loop(i - 1, list.cons(i, acc)) }
}

fn ints(n :: Int) -> List[Int] {
  ints_loop(n, [])
}

# Build a 2-int-column Arrow table once.
fn make_table(n :: Int) -> Result[Table, Str] {
  let xs := ints(n)
  let ys := ints(n)
  arrow.from_int_columns(list.cons(("x", xs), list.cons(("y", ys), [])))
}

# Sum x via the Arrow kernel (one Rust call over a flat i64 buffer).
fn arrow_sum_x(n :: Int) -> Int {
  match make_table(n) {
    Err(_) => -1,
    Ok(t) => match arrow.col_sum_int(t, "x") {
      Ok(s) => s,
      Err(_) => -2,
    },
  }
}

# Mean x via the Arrow kernel.
fn arrow_mean_x(n :: Int) -> Int {
  match make_table(n) {
    Err(_) => -1,
    Ok(t) => match arrow.col_mean(t, "x") {
      Ok(Some(_)) => 1,
      _ => 0,
    },
  }
}

# Min + max + count via Arrow.
fn arrow_min_x(n :: Int) -> Int {
  match make_table(n) {
    Err(_) => -1,
    Ok(t) => match arrow.col_min_int(t, "x") {
      Ok(Some(m)) => m,
      _ => -2,
    },
  }
}

# Amortised sum: build once, reduce k times. Demonstrates that the
# kernel itself is essentially free — when input is already columnar,
# repeated reductions don't cost extra wall-clock.
fn arrow_sum_repeat_loop(t :: Table, k :: Int, acc :: Int) -> Int {
  if k == 0 {
    acc
  } else {
    arrow_sum_repeat_loop(t, k - 1, acc + match arrow.col_sum_int(t, "x") {
      Ok(s) => s,
      Err(_) => 0,
    })
  }
}

fn arrow_sum_repeat(n :: Int, k :: Int) -> Int {
  match make_table(n) {
    Err(_) => -1,
    Ok(t) => arrow_sum_repeat_loop(t, k, 0),
  }
}
