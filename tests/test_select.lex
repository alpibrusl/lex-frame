import "std.list" as list

import "../src/value" as val

import "../src/frame" as frame

import "../src/select" as sel

fn make_df() -> frame.DataFrame {
  let a := list.cons(val.vint(1), list.cons(val.vint(2), list.cons(val.vint(3), [])))
  let b := list.cons(val.vstr("x"), list.cons(val.vstr("y"), list.cons(val.vstr("z"), [])))
  let c := list.cons(val.vfloat(1.1), list.cons(val.vfloat(2.2), list.cons(val.vfloat(3.3), [])))
  let cols := list.cons(("a", a), list.cons(("b", b), list.cons(("c", c), [])))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_select_cols_ncols() -> Int {
  let wanted := list.cons("a", list.cons("c", []))
  match sel.select_cols(make_df(), wanted) {
    Ok(df2) => if list.len(df2.col_names) == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_select_cols_preserves_nrows() -> Int {
  let wanted := list.cons("a", list.cons("c", []))
  match sel.select_cols(make_df(), wanted) {
    Ok(df2) => if df2.nrows == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_select_unknown_col_is_error() -> Int {
  let wanted := list.cons("a", list.cons("z", []))
  match sel.select_cols(make_df(), wanted) {
    Ok(_) => 1,
    Err(_) => 0,
  }
}

fn test_drop_cols_ncols() -> Int {
  let to_drop := list.cons("b", [])
  match sel.drop_cols(make_df(), to_drop) {
    Ok(df2) => if list.len(df2.col_names) == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_rename_col_ncols() -> Int {
  match sel.rename_col(make_df(), "a", "alpha") {
    Ok(df2) => if list.len(df2.col_names) == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_rename_col_nrows() -> Int {
  match sel.rename_col(make_df(), "a", "alpha") {
    Ok(df2) => if df2.nrows == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_rename_unknown_col_is_error() -> Int {
  match sel.rename_col(make_df(), "z", "alpha") {
    Ok(_) => 1,
    Err(_) => 0,
  }
}

fn test_filter_rows_nrows() -> Int {
  let pred := fn (row :: List[(Str, val.Value)]) -> Bool {
    match val.as_int(sel.row_get_or_null(row, "a")) {
      Some(n) => n > 1,
      None => false,
    }
  }
  match sel.filter_rows(make_df(), "a > 1", pred) {
    Ok(df2) => if df2.nrows == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_filter_rows_keeps_ncols() -> Int {
  let pred := fn (row :: List[(Str, val.Value)]) -> Bool {
    match val.as_int(sel.row_get_or_null(row, "a")) {
      Some(n) => n > 1,
      None => false,
    }
  }
  match sel.filter_rows(make_df(), "a > 1", pred) {
    Ok(df2) => if list.len(df2.col_names) == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_with_column_ncols() -> Int {
  let derive := fn (row :: List[(Str, val.Value)]) -> val.Value {
    let gv := sel.row_get_or_null(row, "a")
    match val.as_int(gv) {
      Some(n) => val.vint(n * 2),
      None => gv,
    }
  }
  match sel.with_column(make_df(), "a_doubled", derive) {
    Ok(df2) => if list.len(df2.col_names) == 4 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn run_all() -> Unit {
  let __lex_discard_1 := test_select_cols_ncols() + test_select_cols_preserves_nrows() + test_select_unknown_col_is_error() + test_drop_cols_ncols() + test_rename_col_ncols() + test_rename_col_nrows() + test_rename_unknown_col_is_error() + test_filter_rows_nrows() + test_filter_rows_keeps_ncols() + test_with_column_ncols()
  ()
}

