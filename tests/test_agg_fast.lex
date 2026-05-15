import "std.list" as list
import "std.arrow" as arrow
import "../src/frame" as frame
import "../src/agg" as agg

# Build an arrow-backed DataFrame via std.arrow directly, then exercise
# the new fast-path agg ops. Same workload as test_agg.lex's legacy
# path; the delta is in how `nums` is stored (flat Int64 buffer here
# vs List[Value] there) and which kernel runs (arrow.col_sum_int vs
# col.col_sum walking the list).
fn make_fast_df() -> frame.DataFrame {
  let xs := list.cons(10, list.cons(20, list.cons(30, list.cons(40, []))))
  match arrow.from_int_columns(list.cons(("nums", xs), [])) {
    Ok(t) => frame.from_arrow_table(t),
    Err(_) => frame.empty(),
  }
}

fn test_from_arrow_table_nrows() -> Int {
  if make_fast_df().nrows == 4 {
    0
  } else {
    1
  }
}

fn test_from_arrow_table_col_names() -> Int {
  if list.len(make_fast_df().col_names) == 1 {
    0
  } else {
    1
  }
}

fn test_sum_col_fast() -> Int {
  match agg.sum_col_fast(make_fast_df(), "nums") {
    Some(s) => if s == 100 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_mean_col_fast() -> Int {
  match agg.mean_col_fast(make_fast_df(), "nums") {
    Some(f) => if f == 25.0 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_min_col_fast() -> Int {
  match agg.min_col_fast(make_fast_df(), "nums") {
    Some(n) => if n == 10 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_max_col_fast() -> Int {
  match agg.max_col_fast(make_fast_df(), "nums") {
    Some(n) => if n == 40 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_count_non_null_fast() -> Int {
  if agg.count_non_null_fast(make_fast_df(), "nums") == 4 {
    0
  } else {
    1
  }
}

# Fallback path: a DataFrame built via `from_columns` has arrow_table = None,
# so sum_col_fast routes through the legacy col.col_sum kernel.
# `tests/test_agg.lex` exercises the legacy path directly; this case
# confirms that the _fast variant is API-compatible (same answer).
import "../src/value" as val
fn make_legacy_df() -> frame.DataFrame {
  let nums := list.cons(val.vint(10), list.cons(val.vint(20), list.cons(val.vint(30), list.cons(val.vint(40), []))))
  match frame.from_columns(list.cons(("nums", nums), [])) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_sum_col_fast_falls_back() -> Int {
  match agg.sum_col_fast(make_legacy_df(), "nums") {
    Some(s) => if s == 100 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn run_all() -> Unit {
  let __lex_discard := test_from_arrow_table_nrows() + test_from_arrow_table_col_names() + test_sum_col_fast() + test_mean_col_fast() + test_min_col_fast() + test_max_col_fast() + test_count_non_null_fast() + test_sum_col_fast_falls_back()
  ()
}
