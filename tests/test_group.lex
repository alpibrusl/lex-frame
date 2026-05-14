import "std.list" as list

import "../src/value" as val

import "../src/frame" as frame

import "../src/group" as grp

fn make_df() -> frame.DataFrame {
  let cats := list.cons(val.vstr("A"), list.cons(val.vstr("B"), list.cons(val.vstr("A"), list.cons(val.vstr("B"), []))))
  let vals := list.cons(val.vint(10), list.cons(val.vint(20), list.cons(val.vint(30), list.cons(val.vint(40), []))))
  let cols := list.cons(("cat", cats), list.cons(("val", vals), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_group_by_ngroups() -> Int {
  match grp.group_by(make_df(), "cat") {
    Ok(gf) => if list.len(gf.groups) == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_agg_sum_nrows() -> Int {
  let spec := grp.agg_spec("val_sum", "val", grp.agg_sum())
  let specs := list.cons(spec, [])
  match grp.group_by(make_df(), "cat") {
    Ok(gf) => {
      let result := grp.agg(gf, specs)
      if result.nrows == 2 {
        0
      } else {
        1
      }
    },
    Err(_) => 1,
  }
}

fn test_agg_sum_ncols() -> Int {
  let spec := grp.agg_spec("val_sum", "val", grp.agg_sum())
  let specs := list.cons(spec, [])
  match grp.group_by(make_df(), "cat") {
    Ok(gf) => {
      let result := grp.agg(gf, specs)
      if list.len(result.col_names) == 2 {
        0
      } else {
        1
      }
    },
    Err(_) => 1,
  }
}

fn test_agg_count_nrows() -> Int {
  let spec := grp.agg_spec("count", "val", grp.agg_count())
  let specs := list.cons(spec, [])
  match grp.group_by(make_df(), "cat") {
    Ok(gf) => {
      let result := grp.agg(gf, specs)
      if result.nrows == 2 {
        0
      } else {
        1
      }
    },
    Err(_) => 1,
  }
}

fn test_value_counts_nrows() -> Int {
  match grp.value_counts(make_df(), "cat") {
    Ok(vc) => if vc.nrows == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_value_counts_ncols() -> Int {
  match grp.value_counts(make_df(), "cat") {
    Ok(vc) => if list.len(vc.col_names) == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_group_by_unknown_col_is_error() -> Int {
  match grp.group_by(make_df(), "nonexistent") {
    Ok(_) => 1,
    Err(_) => 0,
  }
}

fn run_all() -> Unit {
  let __lex_discard_1 := test_group_by_ngroups() + test_agg_sum_nrows() + test_agg_sum_ncols() + test_agg_count_nrows() + test_value_counts_nrows() + test_value_counts_ncols() + test_group_by_unknown_col_is_error()
  ()
}

