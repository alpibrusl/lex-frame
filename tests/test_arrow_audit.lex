import "std.list" as list

import "std.str" as str

import "std.arrow" as arrow

import "../src/value" as val

import "../src/frame" as frame

import "../src/select" as sel

import "../src/sort" as srt

import "../src/group" as grp

import "../src/join" as jn

import "../src/agg" as agg

import "../src/stats" as stats

import "../src/inspect" as ins

import "../src/dist" as dist

import "../src/io" as fio

# lex-frame#19: no public op silently returns empty/wrong on an
# arrow-backed frame. Ops with kernel equivalents now produce
# correct results (head/tail/slice, sort_by, select_cols,
# value_counts, the legacy-named agg reductions, null counting,
# inspection); closure/row ops refuse with FRAME_LEGACY_ONLY.
# {x: 1..6, g: 10/20 alternating} as an arrow-backed frame.
fn make_arrow_df() -> frame.DataFrame {
  let xs := list.cons(1, list.cons(2, list.cons(3, list.cons(4, list.cons(5, list.cons(6, []))))))
  let gs := list.cons(10, list.cons(10, list.cons(20, list.cons(20, list.cons(10, list.cons(20, []))))))
  match arrow.from_int_columns(list.cons(("x", xs), list.cons(("g", gs), []))) {
    Ok(t) => frame.from_arrow_table(t),
    Err(_) => frame.empty(),
  }
}

fn arrow_sum(df :: frame.DataFrame, name :: Str) -> Int {
  match df.arrow_table {
    None => 0 - 1,
    Some(t) => match arrow.col_sum_int(t, name) {
      Ok(s) => s,
      Err(_) => 0 - 1,
    },
  }
}

fn is_legacy_only(r :: Result[frame.DataFrame, frame.FrameError]) -> Int {
  match r {
    Err(e) => if e.code == "FRAME_LEGACY_ONLY" {
      0
    } else {
      1
    },
    Ok(_) => 1,
  }
}

# ===== kernel-backed fixes =====
fn test_head_tail_slice_arrow() -> Int {
  let df := make_arrow_df()
  let h := frame.head(df, 2)
  let t := frame.tail(df, 2)
  let s := frame.slice_rows(df, 1, 3)
  let clamped := frame.head(df, 99)
  if h.nrows == 2 and arrow_sum(h, "x") == 3 and t.nrows == 2 and arrow_sum(t, "x") == 11 and s.nrows == 2 and arrow_sum(s, "x") == 5 and clamped.nrows == 6 {
    0
  } else {
    1
  }
}

fn test_sort_by_legacy_name_sorts_arrow() -> Int {
  let sorted := srt.sort_by(make_arrow_df(), "x", false)
  let first := frame.head(sorted, 1)
  if sorted.nrows == 6 and arrow_sum(first, "x") == 6 {
    0
  } else {
    1
  }
}

fn test_select_cols_legacy_name_keeps_arrow() -> Int {
  match sel.select_cols(make_arrow_df(), ["x"]) {
    Err(_) => 1,
    Ok(df2) => if list.len(df2.col_names) == 1 and arrow_sum(df2, "x") == 21 {
      0
    } else {
      1
    },
  }
}

fn test_value_counts_arrow() -> Int {
  match grp.value_counts(make_arrow_df(), "g") {
    Err(_) => 1,
    Ok(vc) => if vc.nrows == 2 and arrow_sum(vc, "count") == 6 {
      0
    } else {
      1
    },
  }
}

fn test_legacy_join_names_delegate_to_kernel() -> Int {
  let l := make_arrow_df()
  let r := make_arrow_df()
  match jn.inner_join(l, r, "x") {
    Err(_) => 1,
    Ok(j) => if j.nrows == 6 {
      0
    } else {
      1
    },
  }
}

fn test_legacy_agg_names_on_arrow() -> Int {
  let df := make_arrow_df()
  let sum_ok := match agg.sum_col(df, "x") {
    Some(v) => match val.as_int(v) {
      Some(n) => n == 21,
      None => false,
    },
    None => false,
  }
  let mean_ok := match agg.mean_col(df, "x") {
    Some(f) => f == 3.5,
    None => false,
  }
  let minmax_ok := match (agg.min_col(df, "x"), agg.max_col(df, "x")) {
    (Some(mn), Some(mx)) => match (val.as_int(mn), val.as_int(mx)) {
      (Some(a), Some(b)) => a == 1 and b == 6,
      (_, _) => false,
    },
    (_, _) => false,
  }
  let count_ok := agg.count_all(df, "x") == 6 and agg.count_non_null(df, "x") == 6 and agg.count_all(df, "nope") == 0
  if sum_ok and mean_ok and minmax_ok and count_ok {
    0
  } else {
    1
  }
}

fn test_null_counts_arrow() -> Int {
  let nc := stats.null_counts(make_arrow_df())
  let total := match agg.sum_col(nc, "null_count") {
    Some(v) => match val.as_int(v) {
      Some(n) => n,
      None => 0 - 1,
    },
    None => 0 - 1,
  }
  if nc.nrows == 2 and total == 0 {
    0
  } else {
    1
  }
}

fn test_null_report_arrow() -> Int {
  let nr := ins.null_report(make_arrow_df())
  let total := match agg.sum_col(nr, "null_count") {
    Some(v) => match val.as_int(v) {
      Some(n) => n,
      None => 0 - 1,
    },
    None => 0 - 1,
  }
  if nr.nrows == 2 and total == 0 {
    0
  } else {
    1
  }
}

fn test_inspect_summary_arrow_dtypes() -> Int {
  let s := ins.summary(make_arrow_df())
  if str.contains(s, "nt64") and str.contains(s, "6 rows x 2 cols") {
    0
  } else {
    1
  }
}

fn test_to_markdown_arrow_marker() -> Int {
  let md := ins.to_markdown(make_arrow_df(), 3)
  if str.contains(md, "not materialized") and str.contains(md, "| x | g |") {
    0
  } else {
    1
  }
}

fn test_column_profile_arrow() -> Int {
  let p := ins.column_profile(make_arrow_df(), "x")
  if str.contains(p, "nt64") and str.contains(p, "mean:     3.5") and str.contains(p, "non-null: 6") {
    0
  } else {
    1
  }
}

fn test_sample_rows_arrow_has_data() -> Int {
  let s := ins.sample_rows(make_arrow_df(), 2)
  if s.nrows == 2 and arrow_sum(s, "x") == 3 {
    0
  } else {
    1
  }
}

# ===== loud refusals =====
fn test_filter_rows_arrow_is_error() -> Int {
  is_legacy_only(sel.filter_rows(make_arrow_df(), "x>0", fn (_row :: List[(Str, val.Value)]) -> Bool {
    true
  }))
}

fn test_with_column_arrow_is_error() -> Int {
  is_legacy_only(sel.with_column(make_arrow_df(), "y", fn (_row :: List[(Str, val.Value)]) -> val.Value {
    val.vint(1)
  }))
}

fn test_rename_col_arrow_is_error() -> Int {
  is_legacy_only(sel.rename_col(make_arrow_df(), "x", "y"))
}

fn test_group_by_arrow_is_error() -> Int {
  match grp.group_by(make_arrow_df(), "g") {
    Err(e) => if e.code == "FRAME_LEGACY_ONLY" {
      0
    } else {
      1
    },
    Ok(_) => 1,
  }
}

fn test_cross_join_arrow_is_error() -> Int {
  is_legacy_only(jn.cross_join(make_arrow_df(), make_arrow_df()))
}

fn test_par_ops_arrow_are_errors() -> Int {
  let a := is_legacy_only(dist.par_apply_col(make_arrow_df(), "x", fn (v :: val.Value) -> val.Value {
    v
  }))
  let b := is_legacy_only(dist.par_map_rows(make_arrow_df(), fn (row :: List[(Str, val.Value)]) -> List[(Str, val.Value)] {
    row
  }))
  a + b
}

fn test_write_csv_arrow_is_error() -> [io] Int {
  match fio.write_csv("/tmp/lex_frame_audit_should_not_exist.csv", make_arrow_df()) {
    Err(e) => if e.code == "FRAME_LEGACY_ONLY" {
      0
    } else {
      1
    },
    Ok(_) => 1,
  }
}

fn fail_if_nonzero(failures :: Int) -> Int {
  1 / if failures == 0 {
    1
  } else {
    0
  }
}

fn run_all() -> [io] Unit {
  let failures := test_head_tail_slice_arrow() + test_sort_by_legacy_name_sorts_arrow() + test_select_cols_legacy_name_keeps_arrow() + test_value_counts_arrow() + test_legacy_join_names_delegate_to_kernel() + test_legacy_agg_names_on_arrow() + test_null_counts_arrow() + test_null_report_arrow() + test_inspect_summary_arrow_dtypes() + test_to_markdown_arrow_marker() + test_column_profile_arrow() + test_sample_rows_arrow_has_data() + test_filter_rows_arrow_is_error() + test_with_column_arrow_is_error() + test_rename_col_arrow_is_error() + test_group_by_arrow_is_error() + test_cross_join_arrow_is_error() + test_par_ops_arrow_are_errors() + test_write_csv_arrow_is_error()
  let __lex_discard := fail_if_nonzero(failures)
  ()
}

