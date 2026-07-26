import "std.list" as list

import "std.arrow" as arrow

import "../src/value" as val

import "../src/frame" as frame

import "../src/select" as sel

import "../src/sort" as srt

import "../src/group" as grp

import "../src/join" as jn

import "../src/io" as fio

# Fast-path ops (std.df routed) against arrow-backed frames, plus the
# legacy fallback on list-backed frames. Values inside an arrow table
# are not directly readable from Lex, so assertions go through the
# arrow reduction kernels (sum / min / max over the result table) and
# frame shape (nrows / col_names / provenance length).
# {x: 1..6, g: 10/20 alternating} as an arrow-backed frame.
fn make_arrow_df() -> frame.DataFrame {
  let xs := list.cons(1, list.cons(2, list.cons(3, list.cons(4, list.cons(5, list.cons(6, []))))))
  let gs := list.cons(10, list.cons(10, list.cons(20, list.cons(20, list.cons(10, list.cons(20, []))))))
  match arrow.from_int_columns(list.cons(("x", xs), list.cons(("g", gs), []))) {
    Ok(t) => frame.from_arrow_table(t),
    Err(_) => frame.empty(),
  }
}

# Same data, list-backed, for fallback coverage.
fn make_legacy_df() -> frame.DataFrame {
  let xs := list.cons(val.vint(1), list.cons(val.vint(2), list.cons(val.vint(3), list.cons(val.vint(4), list.cons(val.vint(5), list.cons(val.vint(6), []))))))
  let gs := list.cons(val.vint(10), list.cons(val.vint(10), list.cons(val.vint(20), list.cons(val.vint(20), list.cons(val.vint(10), list.cons(val.vint(20), []))))))
  match frame.from_columns(list.cons(("x", xs), list.cons(("g", gs), []))) {
    Ok(df) => df,
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

# First row's value of a column in an arrow-backed frame, via a
# 1-row head slice + sum reduction.
fn arrow_first(df :: frame.DataFrame, name :: Str) -> Int {
  match df.arrow_table {
    None => 0 - 1,
    Some(t) => match arrow.col_sum_int(arrow.head(t, 1), name) {
      Ok(s) => s,
      Err(_) => 0 - 1,
    },
  }
}

fn test_filter_gt_int_fast_arrow() -> Int {
  match sel.filter_gt_int_fast(make_arrow_df(), "x", 4) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 2 and arrow_sum(df2, "x") == 11 {
      0
    } else {
      1
    },
  }
}

fn test_filter_eq_int_fast_arrow() -> Int {
  match sel.filter_eq_int_fast(make_arrow_df(), "g", 10) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 3 and arrow_sum(df2, "x") == 8 {
      0
    } else {
      1
    },
  }
}

fn test_filter_lt_int_fast_arrow() -> Int {
  match sel.filter_lt_int_fast(make_arrow_df(), "x", 3) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 2 and arrow_sum(df2, "x") == 3 {
      0
    } else {
      1
    },
  }
}

fn test_filter_fast_unknown_col_arrow() -> Int {
  match sel.filter_gt_int_fast(make_arrow_df(), "nope", 0) {
    Err(e) => if e.code == "SELECT_UNKNOWN_COLUMN" {
      0
    } else {
      1
    },
    Ok(_) => 1,
  }
}

fn test_filter_gt_int_fast_fallback() -> Int {
  match sel.filter_gt_int_fast(make_legacy_df(), "x", 4) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 2 {
      0
    } else {
      1
    },
  }
}

fn test_filter_eq_str_fast_arrow() -> Int {
  let names := list.cons("a", list.cons("b", list.cons("a", [])))
  match arrow.from_str_columns(list.cons(("s", names), [])) {
    Err(_) => 1,
    Ok(t) => match sel.filter_eq_str_fast(frame.from_arrow_table(t), "s", "a") {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 2 {
        0
      } else {
        1
      },
    },
  }
}

fn test_filter_fast_provenance_grows() -> Int {
  let df := make_arrow_df()
  match sel.filter_gt_int_fast(df, "x", 0) {
    Err(_) => 1,
    Ok(df2) => if list.len(df2.provenance) == list.len(df.provenance) + 1 {
      0
    } else {
      1
    },
  }
}

fn test_sort_by_fast_arrow_desc() -> Int {
  let df2 := srt.sort_by_fast(make_arrow_df(), "x", false)
  if df2.nrows == 6 and arrow_first(df2, "x") == 6 {
    0
  } else {
    1
  }
}

fn test_sort_by_fast_arrow_asc() -> Int {
  let df2 := srt.sort_by_fast(srt.sort_by_fast(make_arrow_df(), "x", false), "x", true)
  if arrow_first(df2, "x") == 1 {
    0
  } else {
    1
  }
}

fn test_sort_by_fast_unknown_col_is_identity() -> Int {
  let df := make_arrow_df()
  let df2 := srt.sort_by_fast(df, "nope", true)
  if df2.nrows == df.nrows {
    0
  } else {
    1
  }
}

fn test_sort_by_fast_fallback() -> Int {
  let df2 := srt.sort_by_fast(make_legacy_df(), "x", false)
  match frame.get_row(df2, 0) {
    row => match sel.row_get_or_null(row, "x") {
      v => match val.as_int(v) {
        Some(n) => if n == 6 {
          0
        } else {
          1
        },
        None => 1,
      },
    },
  }
}

fn test_group_agg_fast_arrow() -> Int {
  let specs := list.cons(grp.agg_spec("total", "x", grp.agg_sum()), [])
  match grp.group_agg_fast(make_arrow_df(), "g", specs) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 2 and arrow_sum(df2, "total") == 21 {
      0
    } else {
      1
    },
  }
}

fn test_group_agg_fast_unsupported_op_arrow() -> Int {
  let specs := list.cons(grp.agg_spec("s", "x", grp.agg_std()), [])
  match grp.group_agg_fast(make_arrow_df(), "g", specs) {
    Err(e) => if e.code == "GROUP_UNSUPPORTED_FAST_AGG" {
      0
    } else {
      1
    },
    Ok(_) => 1,
  }
}

fn test_group_agg_fast_fallback() -> Int {
  let specs := list.cons(grp.agg_spec("total", "x", grp.agg_sum()), [])
  match grp.group_agg_fast(make_legacy_df(), "g", specs) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 2 {
      0
    } else {
      1
    },
  }
}

fn make_arrow_pair() -> (frame.DataFrame, frame.DataFrame) {
  let ks := list.cons(1, list.cons(2, list.cons(3, [])))
  let vs := list.cons(100, list.cons(200, list.cons(300, [])))
  let ks2 := list.cons(2, list.cons(3, list.cons(4, [])))
  let ws := list.cons(20, list.cons(30, list.cons(40, [])))
  let left := match arrow.from_int_columns(list.cons(("k", ks), list.cons(("a", vs), []))) {
    Ok(t) => frame.from_arrow_table(t),
    Err(_) => frame.empty(),
  }
  let right := match arrow.from_int_columns(list.cons(("k", ks2), list.cons(("b", ws), []))) {
    Ok(t) => frame.from_arrow_table(t),
    Err(_) => frame.empty(),
  }
  (left, right)
}

fn test_inner_join_fast_arrow() -> Int {
  match make_arrow_pair() {
    (left, right) => match jn.inner_join_fast(left, right, "k") {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 2 and arrow_sum(df2, "b") == 50 {
        0
      } else {
        1
      },
    },
  }
}

fn test_left_join_fast_arrow() -> Int {
  match make_arrow_pair() {
    (left, right) => match jn.left_join_fast(left, right, "k") {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 3 and arrow_sum(df2, "a") == 600 {
        0
      } else {
        1
      },
    },
  }
}

fn test_filter_gt_float_fast_arrow() -> Int {
  let fs := list.cons(1.5, list.cons(2.5, list.cons(3.5, [])))
  match arrow.from_float_columns(list.cons(("f", fs), [])) {
    Err(_) => 1,
    Ok(t) => match sel.filter_gt_float_fast(frame.from_arrow_table(t), "f", 2.0) {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 2 {
        0
      } else {
        1
      },
    },
  }
}

fn test_filter_eq_float_fast_fallback() -> Int {
  let fs := list.cons(val.vfloat(1.5), list.cons(val.vfloat(2.5), []))
  match frame.from_columns(list.cons(("f", fs), [])) {
    Err(_) => 1,
    Ok(df) => match sel.filter_eq_float_fast(df, "f", 2.5) {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 1 {
        0
      } else {
        1
      },
    },
  }
}

fn test_filter_in_str_fast_arrow() -> Int {
  let names := list.cons("a", list.cons("b", list.cons("c", list.cons("a", []))))
  match arrow.from_str_columns(list.cons(("s", names), [])) {
    Err(_) => 1,
    Ok(t) => match sel.filter_in_str_fast(frame.from_arrow_table(t), "s", list.cons("a", list.cons("c", []))) {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 3 {
        0
      } else {
        1
      },
    },
  }
}

# Nulls in an arrow table can only be produced in-memory via an
# unmatched left join (k=1 has no right match, so its "b" is null).
fn make_arrow_with_nulls() -> frame.DataFrame {
  match make_arrow_pair() {
    (left, right) => match jn.left_join_fast(left, right, "k") {
      Err(_) => frame.empty(),
      Ok(df) => df,
    },
  }
}

fn test_filter_isnull_fast_arrow() -> Int {
  match sel.filter_isnull_fast(make_arrow_with_nulls(), "b") {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 1 and arrow_sum(df2, "a") == 100 {
      0
    } else {
      1
    },
  }
}

fn test_filter_notnull_fast_arrow() -> Int {
  match sel.filter_notnull_fast(make_arrow_with_nulls(), "b") {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 2 and arrow_sum(df2, "b") == 50 {
      0
    } else {
      1
    },
  }
}

fn test_drop_nulls_fast_arrow() -> Int {
  match sel.drop_nulls_fast(make_arrow_with_nulls(), list.cons("b", [])) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 2 {
      0
    } else {
      1
    },
  }
}

fn test_filter_isnull_fast_fallback() -> Int {
  let xs := list.cons(val.vint(1), list.cons(val.vnull(), list.cons(val.vint(3), [])))
  match frame.from_columns(list.cons(("x", xs), [])) {
    Err(_) => 1,
    Ok(df) => match sel.filter_isnull_fast(df, "x") {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 1 {
        0
      } else {
        1
      },
    },
  }
}

# {g1, g2, x}: 2x2 key combinations -> 4 groups, total x = 10.
fn test_group_agg_by_keys_fast_arrow() -> Int {
  let g1 := list.cons(1, list.cons(1, list.cons(2, list.cons(2, list.cons(1, [])))))
  let g2 := list.cons(1, list.cons(2, list.cons(1, list.cons(2, list.cons(1, [])))))
  let xs := list.cons(1, list.cons(2, list.cons(3, list.cons(4, list.cons(0, [])))))
  match arrow.from_int_columns(list.cons(("g1", g1), list.cons(("g2", g2), list.cons(("x", xs), [])))) {
    Err(_) => 1,
    Ok(t) => {
      let specs := list.cons(grp.agg_spec("total", "x", grp.agg_sum()), [])
      match grp.group_agg_by_keys_fast(frame.from_arrow_table(t), list.cons("g1", list.cons("g2", [])), specs) {
        Err(_) => 1,
        Ok(df2) => if df2.nrows == 4 and arrow_sum(df2, "total") == 10 {
          0
        } else {
          1
        },
      }
    },
  }
}

fn test_group_multi_key_legacy_is_error() -> Int {
  let specs := list.cons(grp.agg_spec("total", "x", grp.agg_sum()), [])
  match grp.group_agg_by_keys_fast(make_legacy_df(), list.cons("g", list.cons("x", [])), specs) {
    Err(e) => if e.code == "GROUP_MULTI_KEY_NEEDS_ARROW" {
      0
    } else {
      1
    },
    Ok(_) => 1,
  }
}

fn test_join_fast_mixed_backing_is_error() -> Int {
  match make_arrow_pair() {
    (left, _) => match jn.inner_join_fast(left, make_legacy_df(), "g") {
      Err(e) => if e.code == "JOIN_MIXED_BACKING" {
        0
      } else {
        1
      },
      Ok(_) => 1,
    },
  }
}

fn test_join_fast_fallback() -> Int {
  match jn.inner_join_fast(make_legacy_df(), make_legacy_df(), "x") {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 6 {
      0
    } else {
      1
    },
  }
}

fn test_parquet_roundtrip() -> [fs_read, fs_write] Int {
  let path := "/tmp/lex_frame_test_roundtrip.parquet"
  match fio.write_parquet(path, make_arrow_df()) {
    Err(_) => 1,
    Ok(_) => match fio.read_parquet(path) {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 6 and arrow_sum(df2, "x") == 21 {
        0
      } else {
        1
      },
    },
  }
}

fn test_write_parquet_legacy_is_error() -> [fs_write] Int {
  match fio.write_parquet("/tmp/lex_frame_test_legacy.parquet", make_legacy_df()) {
    Err(e) => if e.code == "IO_WRITE_FAILED" {
      0
    } else {
      1
    },
    Ok(_) => 1,
  }
}

fn test_write_csv_fast_roundtrip() -> [fs_read, fs_write] Int {
  let path := "/tmp/lex_frame_test_fast.csv"
  match fio.write_csv_fast(path, make_arrow_df()) {
    Err(_) => 1,
    Ok(_) => match fio.read_csv_fast(path) {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 6 and arrow_sum(df2, "x") == 21 {
        0
      } else {
        1
      },
    },
  }
}

# Fails the file (runtime error: division by zero) when any case
# reports a failure — unlike a silent counter, `lex test` sees this.
fn fail_if_nonzero(failures :: Int) -> Int {
  1 / if failures == 0 {
    1
  } else {
    0
  }
}

fn run_all() -> [fs_read, fs_write] Unit {
  let failures := test_filter_gt_int_fast_arrow() + test_filter_eq_int_fast_arrow() + test_filter_lt_int_fast_arrow() + test_filter_fast_unknown_col_arrow() + test_filter_gt_int_fast_fallback() + test_filter_eq_str_fast_arrow() + test_filter_fast_provenance_grows() + test_sort_by_fast_arrow_desc() + test_sort_by_fast_arrow_asc() + test_sort_by_fast_unknown_col_is_identity() + test_sort_by_fast_fallback() + test_group_agg_fast_arrow() + test_group_agg_fast_unsupported_op_arrow() + test_group_agg_fast_fallback() + test_inner_join_fast_arrow() + test_left_join_fast_arrow() + test_join_fast_mixed_backing_is_error() + test_join_fast_fallback() + test_parquet_roundtrip() + test_write_parquet_legacy_is_error() + test_write_csv_fast_roundtrip() + test_filter_gt_float_fast_arrow() + test_filter_eq_float_fast_fallback() + test_filter_in_str_fast_arrow() + test_filter_isnull_fast_arrow() + test_filter_notnull_fast_arrow() + test_drop_nulls_fast_arrow() + test_filter_isnull_fast_fallback() + test_group_agg_by_keys_fast_arrow() + test_group_multi_key_legacy_is_error()
  let __lex_discard := fail_if_nonzero(failures)
  ()
}

