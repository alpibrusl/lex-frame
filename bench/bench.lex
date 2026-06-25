import "std.list" as list

import "std.str" as str

import "std.int" as int

import "../src/value" as val

import "../src/frame" as frame

import "../src/agg" as agg

import "../src/select" as sel

import "../src/group" as group

import "../src/sort" as srt

# Build [val.vint(1), val.vint(2), ..., val.vint(n)] by prepend.
# Exercises list.cons (PR #405 — VecDeque push_front) and SmolStr-related allocs
# only indirectly (ints, no strings here).
fn build_int_loop(i :: Int, acc :: List[val.Value]) -> List[val.Value] {
  if i == 0 {
    acc
  } else {
    build_int_loop(i - 1, list.cons(val.vint(i), acc))
  }
}

fn build_int_col(n :: Int) -> List[val.Value] {
  build_int_loop(n, [])
}

# Strings cycling through 10 buckets — exercises SmolStr SSO (slice 4)
# every short numeric string ("0".."9") fits inline.
fn build_str_loop(i :: Int, acc :: List[val.Value]) -> List[val.Value] {
  if i == 0 {
    acc
  } else {
    let bucket := i - i / 10 * 10
    build_str_loop(i - 1, list.cons(val.vstr(int.to_str(bucket)), acc))
  }
}

fn build_str_col(n :: Int) -> List[val.Value] {
  build_str_loop(n, [])
}

# A 3-column DataFrame: x (Int), y (Int), g (Str, 10 distinct values).
fn make_df(n :: Int) -> frame.DataFrame {
  let xs := build_int_col(n)
  let ys := build_int_col(n)
  let gs := build_str_col(n)
  let cols := list.cons(("x", xs), list.cons(("y", ys), list.cons(("g", gs), [])))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

# ---- Benchmarks ----
# Build the frame and return row count.
# Exercises: list.cons (PR #405), record construction (Op::MakeRecord),
# map.set folds, function call locals (slice 3 — locals arena).
fn bench_build(n :: Int) -> Int {
  make_df(n).nrows
}

# Column-wise sum of x. Pure column-fold — exercises record field access
# (df.columns, df.col_names, …; PR #407 GetField cache).
fn bench_sum_x(n :: Int) -> Int {
  let df := make_df(n)
  match agg.sum_col(df, "x") {
    Some(VInt(s)) => s,
    _ => -1,
  }
}

fn bench_mean_x(n :: Int) -> Int {
  let df := make_df(n)
  match agg.mean_col(df, "x") {
    Some(_) => 1,
    None => 0,
  }
}

# Filter rows where x is even. Exercises closure dispatch
# (Op::CallClosure → locals arena slice 3) and Map field access.
fn is_even_row(row :: List[(Str, val.Value)]) -> Bool {
  match sel.row_get_or_null(row, "x") {
    VInt(n) => n - n / 2 * 2 == 0,
    _ => false,
  }
}

fn bench_filter(n :: Int) -> Int {
  let df := make_df(n)
  match sel.filter_rows(df, "x_even", is_even_row) {
    Ok(df2) => df2.nrows,
    Err(_) => -1,
  }
}

# Sort by x (numeric, ascending). sort_by returns the sorted frame directly
# (no Result). Exercises sort-driven compare + indexing.
fn bench_sort(n :: Int) -> Int {
  let df := make_df(n)
  srt.sort_by(df, "x", true).nrows
}

# group_by("g") then agg sum(x) and mean(y) — exercises list.cons in
# the per-group accumulator (the #405 hot path), GetField on
# DataFrame/Col/AggSpec records (#407), and lots of fn calls (#409).
fn bench_groupby(n :: Int) -> Int {
  let df := make_df(n)
  let specs := list.cons(group.agg_spec("sum_x", "x", group.agg_sum()), list.cons(group.agg_spec("mean_y", "y", group.agg_mean()), []))
  match group.group_by(df, "g") {
    Err(_) => -1,
    Ok(gf) => group.agg(gf, specs).nrows,
  }
}

