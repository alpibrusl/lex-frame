import "std.list" as list
import "src/value" as val
import "src/frame" as frame
import "src/join" as join

fn make_left() -> frame.DataFrame {
  let ids   = list.cons(val.VInt(1), list.cons(val.VInt(2), list.cons(val.VInt(3), [])))
  let names = list.cons(val.VStr("Alice"), list.cons(val.VStr("Bob"), list.cons(val.VStr("Charlie"), [])))
  let cols  = list.cons(("id", ids), list.cons(("name", names), []))
  match frame.from_columns(cols) {
    Ok(df) => df
    Err(_) => frame.empty()
  }
}

fn make_right() -> frame.DataFrame {
  // id 1 and 2 match; id 4 does not exist in left
  let ids    = list.cons(val.VInt(1), list.cons(val.VInt(2), list.cons(val.VInt(4), [])))
  let scores = list.cons(val.VInt(90), list.cons(val.VInt(85), list.cons(val.VInt(80), [])))
  let cols   = list.cons(("id", ids), list.cons(("score", scores), []))
  match frame.from_columns(cols) {
    Ok(df) => df
    Err(_) => frame.empty()
  }
}

fn test_inner_join_nrows() -> Int {
  match join.inner_join(make_left(), make_right(), "id") {
    Ok(df) => if df.nrows == 2 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_inner_join_ncols() -> Int {
  // left has 2 cols, right has 2 cols; join key counted once => 3
  match join.inner_join(make_left(), make_right(), "id") {
    Ok(df) => if list.len(df.col_names) == 3 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_left_join_nrows() -> Int {
  // All 3 left rows kept; id=3 gets null score
  match join.left_join(make_left(), make_right(), "id") {
    Ok(df) => if df.nrows == 3 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_left_join_ncols() -> Int {
  match join.left_join(make_left(), make_right(), "id") {
    Ok(df) => if list.len(df.col_names) == 3 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_cross_join_nrows() -> Int {
  // 3 left x 3 right = 9
  match join.cross_join(make_left(), make_right()) {
    Ok(df) => if df.nrows == 9 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_cross_join_ncols() -> Int {
  // left 2 + right 2 = 4 (no key dedup in cross join)
  match join.cross_join(make_left(), make_right()) {
    Ok(df) => if list.len(df.col_names) == 4 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_inner_join_unknown_key_is_error() -> Int {
  match join.inner_join(make_left(), make_right(), "no_such_col") {
    Ok(_)  => 1
    Err(_) => 0
  }
}

fn run_all() -> Int {
  test_inner_join_nrows() +
  test_inner_join_ncols() +
  test_left_join_nrows() +
  test_left_join_ncols() +
  test_cross_join_nrows() +
  test_cross_join_ncols() +
  test_inner_join_unknown_key_is_error()
}
