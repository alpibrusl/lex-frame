import "std.list" as list

import "../src/value" as val

import "../src/frame" as frame

import "../src/stats" as stats

fn make_df() -> frame.DataFrame {
  let a := list.cons(val.vint(1), list.cons(val.vint(2), list.cons(val.vint(3), list.cons(val.vint(4), list.cons(val.vint(5), [])))))
  let b := list.cons(val.vfloat(2.0), list.cons(val.vfloat(4.0), list.cons(val.vfloat(6.0), list.cons(val.vfloat(8.0), list.cons(val.vfloat(10.0), [])))))
  let cols := list.cons(("a", a), list.cons(("b", b), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn make_df_with_nulls() -> frame.DataFrame {
  let a := list.cons(val.vint(1), list.cons(val.vnull(), list.cons(val.vint(3), [])))
  let text := list.cons(val.vstr("x"), list.cons(val.vstr("y"), list.cons(val.vnull(), [])))
  let cols := list.cons(("a", a), list.cons(("text", text), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_describe_nrows() -> Int {
  let desc := stats.describe(make_df())
  if desc.nrows == 5 {
    0
  } else {
    1
  }
}

fn test_describe_ncols() -> Int {
  let desc := stats.describe(make_df())
  if list.len(desc.col_names) == 3 {
    0
  } else {
    1
  }
}

fn test_describe_preserves_input_nrows() -> Int {
  let df := make_df()
  let __lex_discard_1 := stats.describe(df)
  if df.nrows == 5 {
    0
  } else {
    1
  }
}

fn test_null_counts_nrows() -> Int {
  let nc := stats.null_counts(make_df_with_nulls())
  if nc.nrows == 2 {
    0
  } else {
    1
  }
}

fn test_null_counts_ncols() -> Int {
  let nc := stats.null_counts(make_df_with_nulls())
  if list.len(nc.col_names) == 3 {
    0
  } else {
    1
  }
}

fn test_correlation_perfect_positive() -> Int {
  match stats.correlation(make_df(), "a", "b") {
    Some(r) => if r > 0.99 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_correlation_same_col_is_one() -> Int {
  match stats.correlation(make_df(), "a", "a") {
    Some(r) => if r > 0.99 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_correlation_unknown_col_is_none() -> Int {
  match stats.correlation(make_df(), "a", "nonexistent") {
    Some(_) => 1,
    None => 0,
  }
}

fn run_all() -> Unit {
  let __lex_discard_2 := test_describe_nrows() + test_describe_ncols() + test_describe_preserves_input_nrows() + test_null_counts_nrows() + test_null_counts_ncols() + test_correlation_perfect_positive() + test_correlation_same_col_is_one() + test_correlation_unknown_col_is_none()
  ()
}

