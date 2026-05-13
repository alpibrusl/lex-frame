import "std.list" as list
import "src/value" as val
import "src/frame" as frame
import "src/group" as grp

fn make_df() -> frame.DataFrame {
  let cats = list.cons(val.VStr("A"), list.cons(val.VStr("B"), list.cons(val.VStr("A"), list.cons(val.VStr("B"), []))))
  let vals = list.cons(val.VInt(10), list.cons(val.VInt(20), list.cons(val.VInt(30), list.cons(val.VInt(40), []))))
  let cols = list.cons(("cat", cats), list.cons(("val", vals), []))
  match frame.from_columns(cols) {
    Ok(df) => df
    Err(_) => frame.empty()
  }
}

fn test_group_by_ngroups() -> Int {
  let key_cols = list.cons("cat", [])
  match grp.group_by(make_df(), key_cols) {
    Ok(gf) => if list.len(gf.groups) == 2 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_agg_sum_nrows() -> Int {
  let key_cols = list.cons("cat", [])
  let spec     = { col_name = "val", op = grp.AggSum, result_name = "val_sum" }
  let specs    = list.cons(spec, [])
  match grp.group_by(make_df(), key_cols) {
    Ok(gf) => match grp.agg(gf, specs) {
      Ok(result) => if result.nrows == 2 { 0 } else { 1 }
      Err(_)     => 1
    }
    Err(_) => 1
  }
}

fn test_agg_sum_ncols() -> Int {
  let key_cols = list.cons("cat", [])
  let spec     = { col_name = "val", op = grp.AggSum, result_name = "val_sum" }
  let specs    = list.cons(spec, [])
  match grp.group_by(make_df(), key_cols) {
    Ok(gf) => match grp.agg(gf, specs) {
      // key col + one agg result col
      Ok(result) => if list.len(result.col_names) == 2 { 0 } else { 1 }
      Err(_)     => 1
    }
    Err(_) => 1
  }
}

fn test_agg_count_nrows() -> Int {
  let key_cols = list.cons("cat", [])
  let spec     = { col_name = "val", op = grp.AggCount, result_name = "count" }
  let specs    = list.cons(spec, [])
  match grp.group_by(make_df(), key_cols) {
    Ok(gf) => match grp.agg(gf, specs) {
      Ok(result) => if result.nrows == 2 { 0 } else { 1 }
      Err(_)     => 1
    }
    Err(_) => 1
  }
}

fn test_value_counts_nrows() -> Int {
  match grp.value_counts(make_df(), "cat") {
    Ok(vc) => if vc.nrows == 2 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_value_counts_ncols() -> Int {
  match grp.value_counts(make_df(), "cat") {
    Ok(vc) => if list.len(vc.col_names) == 2 { 0 } else { 1 }
    Err(_) => 1
  }
}

fn test_group_by_unknown_col_is_error() -> Int {
  let key_cols = list.cons("nonexistent", [])
  match grp.group_by(make_df(), key_cols) {
    Ok(_)  => 1
    Err(_) => 0
  }
}

fn run_all() -> Int {
  test_group_by_ngroups() +
  test_agg_sum_nrows() +
  test_agg_sum_ncols() +
  test_agg_count_nrows() +
  test_value_counts_nrows() +
  test_value_counts_ncols() +
  test_group_by_unknown_col_is_error()
}
