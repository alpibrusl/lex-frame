import "std.list" as list
import "../src/value" as val
import "../src/frame" as frame
import "../src/agg" as agg

fn make_df() -> frame.DataFrame {
  let nums   := list.cons(val.VInt(10), list.cons(val.VInt(20), list.cons(val.VInt(30), list.cons(val.VNull, []))))
  let floats := list.cons(val.VFloat(1.0), list.cons(val.VFloat(2.0), list.cons(val.VFloat(3.0), list.cons(val.VFloat(4.0), []))))
  let cols   := list.cons(("nums", nums), list.cons(("floats", floats), []))
  match frame.from_columns(cols) {
    Ok(df) => df
    Err(_) => frame.empty()
  }
}

fn test_count_all() -> Int {
  if agg.count_all(make_df(), "nums") == 4 { 0 } else { 1 }
}

fn test_count_non_null() -> Int {
  if agg.count_non_null(make_df(), "nums") == 3 { 0 } else { 1 }
}

fn test_sum_col_int() -> Int {
  match agg.sum_col(make_df(), "nums") {
    Some(val.VInt(n)) => if n == 60 { 0 } else { 1 }
    _ => 1
  }
}

fn test_sum_col_float() -> Int {
  match agg.sum_col(make_df(), "floats") {
    Some(val.VFloat(f)) => if f == 10.0 { 0 } else { 1 }
    _ => 1
  }
}

fn test_mean_col_int() -> Int {
  match agg.mean_col(make_df(), "nums") {
    Some(f) => if f == 20.0 { 0 } else { 1 }
    None => 1
  }
}

fn test_min_col_int() -> Int {
  match agg.min_col(make_df(), "nums") {
    Some(val.VInt(n)) => if n == 10 { 0 } else { 1 }
    _ => 1
  }
}

fn test_max_col_int() -> Int {
  match agg.max_col(make_df(), "nums") {
    Some(val.VInt(n)) => if n == 30 { 0 } else { 1 }
    _ => 1
  }
}

fn test_min_col_float() -> Int {
  match agg.min_col(make_df(), "floats") {
    Some(val.VFloat(f)) => if f == 1.0 { 0 } else { 1 }
    _ => 1
  }
}

fn test_max_col_float() -> Int {
  match agg.max_col(make_df(), "floats") {
    Some(val.VFloat(f)) => if f == 4.0 { 0 } else { 1 }
    _ => 1
  }
}

fn test_n_distinct_with_null() -> Int {
  # [10, 20, 30, null] => 4 distinct values
  if agg.n_distinct(make_df(), "nums") == 4 { 0 } else { 1 }
}

fn test_n_distinct_float() -> Int {
  # [1.0, 2.0, 3.0, 4.0] => 4 distinct
  if agg.n_distinct(make_df(), "floats") == 4 { 0 } else { 1 }
}

fn test_count_all_float() -> Int {
  if agg.count_all(make_df(), "floats") == 4 { 0 } else { 1 }
}

fn test_count_non_null_no_nulls() -> Int {
  if agg.count_non_null(make_df(), "floats") == 4 { 0 } else { 1 }
}

fn run_all() -> Int {
  test_count_all() +
  test_count_non_null() +
  test_sum_col_int() +
  test_sum_col_float() +
  test_mean_col_int() +
  test_min_col_int() +
  test_max_col_int() +
  test_min_col_float() +
  test_max_col_float() +
  test_n_distinct_with_null() +
  test_n_distinct_float() +
  test_count_all_float() +
  test_count_non_null_no_nulls()
}
