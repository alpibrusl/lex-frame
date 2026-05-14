import "std.list" as list

import "../src/value" as val

import "../src/frame" as frame

import "../src/agg" as agg

fn make_df() -> frame.DataFrame {
  let nums := list.cons(val.vint(10), list.cons(val.vint(20), list.cons(val.vint(30), list.cons(val.vnull(), []))))
  let floats := list.cons(val.vfloat(1.0), list.cons(val.vfloat(2.0), list.cons(val.vfloat(3.0), list.cons(val.vfloat(4.0), []))))
  let cols := list.cons(("nums", nums), list.cons(("floats", floats), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_count_all() -> Int {
  if agg.count_all(make_df(), "nums") == 4 {
    0
  } else {
    1
  }
}

fn test_count_non_null() -> Int {
  if agg.count_non_null(make_df(), "nums") == 3 {
    0
  } else {
    1
  }
}

fn test_sum_col_int() -> Int {
  match agg.sum_col(make_df(), "nums") {
    Some(v) => match val.as_int(v) {
      Some(n) => if n == 60 {
        0
      } else {
        1
      },
      None => 1,
    },
    None => 1,
  }
}

fn test_sum_col_float() -> Int {
  match agg.sum_col(make_df(), "floats") {
    Some(v) => match val.as_float(v) {
      Some(f) => if f == 10.0 {
        0
      } else {
        1
      },
      None => 1,
    },
    None => 1,
  }
}

fn test_mean_col_int() -> Int {
  match agg.mean_col(make_df(), "nums") {
    Some(f) => if f == 20.0 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_min_col_int() -> Int {
  match agg.min_col(make_df(), "nums") {
    Some(v) => match val.as_int(v) {
      Some(n) => if n == 10 {
        0
      } else {
        1
      },
      None => 1,
    },
    None => 1,
  }
}

fn test_max_col_int() -> Int {
  match agg.max_col(make_df(), "nums") {
    Some(v) => match val.as_int(v) {
      Some(n) => if n == 30 {
        0
      } else {
        1
      },
      None => 1,
    },
    None => 1,
  }
}

fn test_min_col_float() -> Int {
  match agg.min_col(make_df(), "floats") {
    Some(v) => match val.as_float(v) {
      Some(f) => if f == 1.0 {
        0
      } else {
        1
      },
      None => 1,
    },
    None => 1,
  }
}

fn test_max_col_float() -> Int {
  match agg.max_col(make_df(), "floats") {
    Some(v) => match val.as_float(v) {
      Some(f) => if f == 4.0 {
        0
      } else {
        1
      },
      None => 1,
    },
    None => 1,
  }
}

fn test_n_distinct_with_null() -> Int {
  if agg.n_distinct(make_df(), "nums") == 4 {
    0
  } else {
    1
  }
}

fn test_n_distinct_float() -> Int {
  if agg.n_distinct(make_df(), "floats") == 4 {
    0
  } else {
    1
  }
}

fn test_count_all_float() -> Int {
  if agg.count_all(make_df(), "floats") == 4 {
    0
  } else {
    1
  }
}

fn test_count_non_null_no_nulls() -> Int {
  if agg.count_non_null(make_df(), "floats") == 4 {
    0
  } else {
    1
  }
}

fn run_all() -> Unit {
  let __lex_discard_1 := test_count_all() + test_count_non_null() + test_sum_col_int() + test_sum_col_float() + test_mean_col_int() + test_min_col_int() + test_max_col_int() + test_min_col_float() + test_max_col_float() + test_n_distinct_with_null() + test_n_distinct_float() + test_count_all_float() + test_count_non_null_no_nulls()
  ()
}

