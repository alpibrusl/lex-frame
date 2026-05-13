import "std.list" as list

import "../src/value" as val

import "../src/frame" as frame

fn make_df() -> frame.DataFrame {
  let names := list.cons(val.vstr("Alice"), list.cons(val.vstr("Bob"), list.cons(val.vstr("Charlie"), [])))
  let ages := list.cons(val.vint(25), list.cons(val.vint(30), list.cons(val.vint(35), [])))
  let cols := list.cons(("name", names), list.cons(("age", ages), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_empty_nrows() -> Int {
  if frame.empty().nrows == 0 {
    0
  } else {
    1
  }
}

fn test_from_columns_nrows() -> Int {
  if make_df().nrows == 3 {
    0
  } else {
    1
  }
}

fn test_from_columns_ncols() -> Int {
  if list.len(make_df().col_names) == 2 {
    0
  } else {
    1
  }
}

fn test_head_nrows() -> Int {
  if frame.head(make_df(), 2).nrows == 2 {
    0
  } else {
    1
  }
}

fn test_head_all() -> Int {
  if frame.head(make_df(), 10).nrows == 3 {
    0
  } else {
    1
  }
}

fn test_tail_nrows() -> Int {
  if frame.tail(make_df(), 2).nrows == 2 {
    0
  } else {
    1
  }
}

fn test_slice_rows() -> Int {
  if frame.slice_rows(make_df(), 1, 3).nrows == 2 {
    0
  } else {
    1
  }
}

fn test_slice_empty() -> Int {
  if frame.slice_rows(make_df(), 2, 2).nrows == 0 {
    0
  } else {
    1
  }
}

fn test_add_column_ncols() -> Int {
  let df := make_df()
  let scores := list.cons(val.vint(90), list.cons(val.vint(85), list.cons(val.vint(95), [])))
  match frame.add_column(df, "score", scores) {
    Ok(df2) => if list.len(df2.col_names) == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_add_column_nrows() -> Int {
  let df := make_df()
  let scores := list.cons(val.vint(90), list.cons(val.vint(85), list.cons(val.vint(95), [])))
  match frame.add_column(df, "score", scores) {
    Ok(df2) => if df2.nrows == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_add_column_length_mismatch() -> Int {
  let df := make_df()
  let scores := list.cons(val.vint(90), [])
  match frame.add_column(df, "score", scores) {
    Ok(_) => 1,
    Err(_) => 0,
  }
}

fn test_drop_column_ncols() -> Int {
  match frame.drop_column(make_df(), "age") {
    Ok(df2) => if list.len(df2.col_names) == 1 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_drop_unknown_column() -> Int {
  match frame.drop_column(make_df(), "nonexistent") {
    Ok(_) => 1,
    Err(_) => 0,
  }
}

fn test_from_columns_length_mismatch() -> Int {
  let name_col := list.cons(val.vstr("Alice"), list.cons(val.vstr("Bob"), []))
  let age_col := list.cons(val.vint(25), [])
  let cols := list.cons(("name", name_col), list.cons(("age", age_col), []))
  match frame.from_columns(cols) {
    Ok(_) => 1,
    Err(_) => 0,
  }
}

fn test_get_row_len() -> Int {
  let row := frame.get_row(make_df(), 0)
  if list.len(row) == 2 {
    0
  } else {
    1
  }
}

fn run_all() -> Unit {
  let __lex_discard_1 := test_empty_nrows() + test_from_columns_nrows() + test_from_columns_ncols() + test_head_nrows() + test_head_all() + test_tail_nrows() + test_slice_rows() + test_slice_empty() + test_add_column_ncols() + test_add_column_nrows() + test_add_column_length_mismatch() + test_drop_column_ncols() + test_drop_unknown_column() + test_from_columns_length_mismatch() + test_get_row_len()
  ()
}

