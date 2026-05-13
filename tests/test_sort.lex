import "std.list" as list

import "../src/value" as val

import "../src/frame" as frame

import "../src/sort" as srt

import "../src/select" as sel

fn make_df() -> frame.DataFrame {
  let ages := list.cons(val.vint(30), list.cons(val.vint(25), list.cons(val.vint(35), list.cons(val.vint(20), []))))
  let names := list.cons(val.vstr("Charlie"), list.cons(val.vstr("Alice"), list.cons(val.vstr("Dave"), list.cons(val.vstr("Bob"), []))))
  let cols := list.cons(("age", ages), list.cons(("name", names), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_sort_preserves_nrows() -> Int {
  if srt.sort_by(make_df(), "age", true).nrows == 4 {
    0
  } else {
    1
  }
}

fn test_sort_preserves_ncols() -> Int {
  if list.len(srt.sort_by(make_df(), "age", true).col_names) == 2 {
    0
  } else {
    1
  }
}

fn test_sort_asc_first_is_min() -> Int {
  let sorted := srt.sort_by(make_df(), "age", true)
  let row := frame.get_row(sorted, 0)
  match val.as_int(sel.row_get_or_null(row, "age")) {
    Some(n) => if n == 20 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_sort_asc_last_is_max() -> Int {
  let sorted := srt.sort_by(make_df(), "age", true)
  let row := frame.get_row(sorted, 3)
  match val.as_int(sel.row_get_or_null(row, "age")) {
    Some(n) => if n == 35 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_sort_desc_first_is_max() -> Int {
  let sorted := srt.sort_by(make_df(), "age", false)
  let row := frame.get_row(sorted, 0)
  match val.as_int(sel.row_get_or_null(row, "age")) {
    Some(n) => if n == 35 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_sort_preserves_row_alignment() -> Int {
  let sorted := srt.sort_by(make_df(), "age", true)
  let row := frame.get_row(sorted, 0)
  match val.as_str(sel.row_get_or_null(row, "name")) {
    Some(s) => if s == "Bob" {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_sort_by_cols_nrows() -> Int {
  let specs := list.cons(("age", true), [])
  if srt.sort_by_cols(make_df(), specs).nrows == 4 {
    0
  } else {
    1
  }
}

fn run_all() -> Unit {
  let __lex_discard_1 := test_sort_preserves_nrows() + test_sort_preserves_ncols() + test_sort_asc_first_is_min() + test_sort_asc_last_is_max() + test_sort_desc_first_is_max() + test_sort_preserves_row_alignment() + test_sort_by_cols_nrows()
  ()
}

