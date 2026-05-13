import "std.list" as list
import "../src/value" as val
import "../src/frame" as frame
import "../src/stats" as stats

fn make_df() -> frame.DataFrame {
  let a    := list.cons(val.VInt(1), list.cons(val.VInt(2), list.cons(val.VInt(3), list.cons(val.VInt(4), list.cons(val.VInt(5), [])))))
  let b    := list.cons(val.VFloat(2.0), list.cons(val.VFloat(4.0), list.cons(val.VFloat(6.0), list.cons(val.VFloat(8.0), list.cons(val.VFloat(10.0), [])))))
  let cols := list.cons(("a", a), list.cons(("b", b), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn make_df_with_nulls() -> frame.DataFrame {
  let a    := list.cons(val.VInt(1), list.cons(val.VNull, list.cons(val.VInt(3), [])))
  let text := list.cons(val.VStr("x"), list.cons(val.VStr("y"), list.cons(val.VNull, [])))
  let cols := list.cons(("a", a), list.cons(("text", text), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_describe_nrows() -> Int {
  # describe returns 5 summary rows: count, mean, std, min, max
  let desc := stats.describe(make_df())
  if desc.nrows == 5 { 0 } else { 1 }
}

fn test_describe_ncols() -> Int {
  # 1 stat-label col + 2 numeric cols
  let desc := stats.describe(make_df())
  if list.len(desc.col_names) == 3 { 0 } else { 1 }
}

fn test_describe_preserves_input_nrows() -> Int {
  # describe must not mutate the source df
  let df := make_df()
  let _  := stats.describe(df)
  if df.nrows == 5 { 0 } else { 1 }
}

fn test_null_counts_nrows() -> Int {
  # one row per column
  let nc := stats.null_counts(make_df_with_nulls())
  if nc.nrows == 2 { 0 } else { 1 }
}

fn test_null_counts_ncols() -> Int {
  # columns: column_name, null_count, null_pct
  let nc := stats.null_counts(make_df_with_nulls())
  if list.len(nc.col_names) == 3 { 0 } else { 1 }
}

fn test_correlation_perfect_positive() -> Int {
  # a and b are perfectly positively correlated
  match stats.correlation(make_df(), "a", "b") {
    Some(r) => if r > 0.99 { 0 } else { 1 },
    None => 1,
  }
}

fn test_correlation_same_col_is_one() -> Int {
  match stats.correlation(make_df(), "a", "a") {
    Some(r) => if r > 0.99 { 0 } else { 1 },
    None => 1,
  }
}

fn test_correlation_unknown_col_is_none() -> Int {
  match stats.correlation(make_df(), "a", "nonexistent") {
    Some(_) => 1,
    None    => 0,
  }
}

fn run_all() -> () {
  let _ := test_describe_nrows() + test_describe_ncols() +
            test_describe_preserves_input_nrows() + test_null_counts_nrows() +
            test_null_counts_ncols() + test_correlation_perfect_positive() +
            test_correlation_same_col_is_one() + test_correlation_unknown_col_is_none()
  ()
}
