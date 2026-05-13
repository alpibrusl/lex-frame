import "std.list" as list

import "../src/value" as val

import "../src/frame" as frame

import "../src/join" as join

fn make_left() -> frame.DataFrame {
  let ids := list.cons(val.vint(1), list.cons(val.vint(2), list.cons(val.vint(3), [])))
  let names := list.cons(val.vstr("Alice"), list.cons(val.vstr("Bob"), list.cons(val.vstr("Charlie"), [])))
  let cols := list.cons(("id", ids), list.cons(("name", names), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn make_right() -> frame.DataFrame {
  let ids := list.cons(val.vint(1), list.cons(val.vint(2), list.cons(val.vint(4), [])))
  let scores := list.cons(val.vint(90), list.cons(val.vint(85), list.cons(val.vint(80), [])))
  let cols := list.cons(("id", ids), list.cons(("score", scores), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_inner_join_nrows() -> Int {
  match join.inner_join(make_left(), make_right(), "id") {
    Ok(df) => if df.nrows == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_inner_join_ncols() -> Int {
  match join.inner_join(make_left(), make_right(), "id") {
    Ok(df) => if list.len(df.col_names) == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_left_join_nrows() -> Int {
  match join.left_join(make_left(), make_right(), "id") {
    Ok(df) => if df.nrows == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_left_join_ncols() -> Int {
  match join.left_join(make_left(), make_right(), "id") {
    Ok(df) => if list.len(df.col_names) == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_cross_join_nrows() -> Int {
  match join.cross_join(make_left(), make_right()) {
    Ok(df) => if df.nrows == 9 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_cross_join_ncols() -> Int {
  match join.cross_join(make_left(), make_right()) {
    Ok(df) => if list.len(df.col_names) == 4 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_inner_join_unknown_key_is_error() -> Int {
  match join.inner_join(make_left(), make_right(), "no_such_col") {
    Ok(_) => 1,
    Err(_) => 0,
  }
}

fn run_all() -> Unit {
  let __lex_discard_1 := test_inner_join_nrows() + test_inner_join_ncols() + test_left_join_nrows() + test_left_join_ncols() + test_cross_join_nrows() + test_cross_join_ncols() + test_inner_join_unknown_key_is_error()
  ()
}

