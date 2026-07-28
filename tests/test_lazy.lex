import "std.list" as list

import "std.str" as str

import "std.arrow" as arrow

import "../src/value" as val

import "../src/frame" as frame

import "../src/select" as sel

import "../src/group" as grp

import "../src/lazy" as lazy

import "../src/io" as fio

# Lazy plans (lex-frame#16): every case cross-checks `lazy.collect`
# against the eager `_fast` pipeline it replaces — same kernels, so
# results must match exactly. Assertions read arrow-backed results
# through the reduction kernels, like tests/test_fast_ops.lex.
# {x: 1..6, g: 10/20 alternating} as an arrow-backed frame.
fn make_arrow_df() -> frame.DataFrame {
  let xs := list.cons(1, list.cons(2, list.cons(3, list.cons(4, list.cons(5, list.cons(6, []))))))
  let gs := list.cons(10, list.cons(10, list.cons(20, list.cons(20, list.cons(10, list.cons(20, []))))))
  match arrow.from_int_columns(list.cons(("x", xs), list.cons(("g", gs), []))) {
    Ok(t) => frame.from_arrow_table(t),
    Err(_) => frame.empty(),
  }
}

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

fn arrow_first(df :: frame.DataFrame, name :: Str) -> Int {
  match df.arrow_table {
    None => 0 - 1,
    Some(t) => match arrow.col_sum_int(arrow.head(t, 1), name) {
      Ok(s) => s,
      Err(_) => 0 - 1,
    },
  }
}

# filter -> sort -> collect matches the eager pipeline result.
fn test_collect_matches_eager() -> Int {
  let lazy_res := lazy.collect_frame(lazy.sort_by(lazy.filter_gt_int(lazy.from_frame(make_arrow_df()), "x", 2), "x", false))
  let eager_res := match sel.filter_gt_int_fast(make_arrow_df(), "x", 2) {
    Err(_) => Err(frame.frame_err("X", "eager filter failed", "")),
    Ok(df2) => Ok(srt_desc(df2)),
  }
  match (lazy_res, eager_res) {
    (Ok(a), Ok(b)) => if a.nrows == b.nrows and arrow_sum(a, "x") == arrow_sum(b, "x") and arrow_first(a, "x") == arrow_first(b, "x") and arrow_first(a, "x") == 6 {
      0
    } else {
      1
    },
    (_, _) => 1,
  }
}

fn srt_desc(df :: frame.DataFrame) -> frame.DataFrame {
  match df.arrow_table {
    None => df,
    Some(_) => match lazy.collect_frame(lazy.sort_by(lazy.from_frame(df), "x", false)) {
      Err(_) => df,
      Ok(d) => d,
    },
  }
}

# A filter placed AFTER a select that drops its column still works:
# the rewrite hoists the filter above the select (issue #16
# acceptance criterion). Eager in this order fails on arrow frames.
fn test_filter_survives_later_select() -> Int {
  let plan2 := lazy.filter_eq_int(lazy.select_cols(lazy.from_frame(make_arrow_df()), ["x"]), "g", 10)
  match lazy.collect_frame(plan2) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 3 and arrow_sum(df2, "x") == 8 and list.len(df2.col_names) == 1 {
      0
    } else {
      1
    },
  }
}

# Same plan run eagerly errors — documents the intended divergence.
fn test_eager_order_would_fail() -> Int {
  match sel.select_cols_fast(make_arrow_df(), ["x"]) {
    Err(_) => 1,
    Ok(df2) => match sel.filter_eq_int_fast(df2, "g", 10) {
      Err(_) => 0,
      Ok(_) => 1,
    },
  }
}

# No narrowing op in the plan -> no pruning -> all columns survive.
fn test_no_narrowing_keeps_all_cols() -> Int {
  match lazy.collect_frame(lazy.filter_gt_int(lazy.from_frame(make_arrow_df()), "x", 4)) {
    Err(_) => 1,
    Ok(df2) => if list.len(df2.col_names) == 2 and df2.nrows == 2 {
      0
    } else {
      1
    },
  }
}

# group_agg with a multi-spec list runs as one node and matches eager.
fn test_group_agg_matches_eager() -> Int {
  let specs := list.cons(grp.agg_spec("sx", "x", grp.AggSum), list.cons(grp.agg_spec("mx", "x", grp.AggMax), []))
  let lazy_res := lazy.collect_frame(lazy.group_agg(lazy.from_frame(make_arrow_df()), ["g"], specs))
  let eager_res := grp.group_agg_by_keys_fast(make_arrow_df(), ["g"], specs)
  match (lazy_res, eager_res) {
    (Ok(a), Ok(b)) => if a.nrows == b.nrows and a.nrows == 2 and arrow_sum(a, "sx") == arrow_sum(b, "sx") and arrow_sum(a, "sx") == 21 and arrow_sum(a, "mx") == arrow_sum(b, "mx") {
      0
    } else {
      1
    },
    (_, _) => 1,
  }
}

# Filter + group_agg: pruning kicks in (group_agg narrows), filter
# hoisted, result matches eager filter-then-group.
fn test_filter_group_pruned_matches_eager() -> Int {
  let specs := list.cons(grp.agg_spec("sx", "x", grp.AggSum), [])
  let lazy_res := lazy.collect_frame(lazy.group_agg(lazy.filter_gt_int(lazy.from_frame(make_arrow_df()), "x", 1), ["g"], specs))
  let eager_res := match sel.filter_gt_int_fast(make_arrow_df(), "x", 1) {
    Err(e) => Err(e),
    Ok(df2) => grp.group_agg_by_keys_fast(df2, ["g"], specs),
  }
  match (lazy_res, eager_res) {
    (Ok(a), Ok(b)) => if a.nrows == b.nrows and arrow_sum(a, "sx") == arrow_sum(b, "sx") and arrow_sum(a, "sx") == 20 {
      0
    } else {
      1
    },
    (_, _) => 1,
  }
}

# A misspelled column anywhere in a pruned plan is a loud error.
fn test_unknown_col_in_pruned_plan_is_error() -> Int {
  let specs := list.cons(grp.agg_spec("sx", "nope", grp.AggSum), [])
  match lazy.collect_frame(lazy.group_agg(lazy.from_frame(make_arrow_df()), ["g"], specs)) {
    Err(e) => if e.code == "SELECT_UNKNOWN_COLUMN" {
      0
    } else {
      1
    },
    Ok(_) => 1,
  }
}

# Legacy (list-backed) frames run through the same plan API via the
# eager fallbacks.
fn test_legacy_frame_collect() -> Int {
  match lazy.collect_frame(lazy.filter_gt_int(lazy.from_frame(make_legacy_df()), "x", 4)) {
    Err(_) => 1,
    Ok(df2) => if df2.nrows == 2 {
      0
    } else {
      1
    },
  }
}

fn nth_line(lines :: List[Str], i :: Int) -> Str {
  match list.fold(list.enumerate(lines), None, fn (acc :: Option[Str], p :: (Int, Str)) -> Option[Str] {
    match acc {
      Some(_) => acc,
      None => match p {
        (idx, l) => if idx == i {
          Some(l)
        } else {
          None
        },
      },
    }
  }) {
    Some(l) => l,
    None => "",
  }
}

# explain(): source line carries the pruned projection; the filter
# declared LAST comes out before the select/sort it was declared
# after (hoisting), and select/sort keep their relative order.
fn test_explain_shows_rewrites() -> Int {
  let plan := lazy.filter_eq_int(lazy.sort_by(lazy.select_cols(lazy.from_frame(make_arrow_df()), ["x", "g"]), "x", true), "g", 10)
  let lines := lazy.explain(plan)
  let src_ok := str.contains(nth_line(lines, 0), "project=[g,x]")
  let hoisted := nth_line(lines, 1) == "filter g == 10"
  let select_then_sort := nth_line(lines, 2) == "select [x,g]" and nth_line(lines, 3) == "sort x asc"
  if src_ok and hoisted and select_then_sort and list.len(lines) == 4 {
    0
  } else {
    1
  }
}

# Parquet scan: pruning pushes the projection into the reader; result
# matches the unpruned eager pipeline.
fn test_scan_parquet_pruned_matches_eager() -> [fs_read, fs_write] Int {
  let path := "/tmp/lex_frame_test_lazy.parquet"
  match fio.write_parquet(path, make_arrow_df()) {
    Err(_) => 1,
    Ok(_) => {
      let specs := list.cons(grp.agg_spec("sx", "x", grp.AggSum), [])
      let lazy_res := lazy.collect(lazy.group_agg(lazy.filter_gt_int(lazy.scan_parquet(path), "x", 1), ["g"], specs))
      let eager_res := match fio.read_parquet(path) {
        Err(e) => Err(e),
        Ok(df) => match sel.filter_gt_int_fast(df, "x", 1) {
          Err(e) => Err(e),
          Ok(df2) => grp.group_agg_by_keys_fast(df2, ["g"], specs),
        },
      }
      match (lazy_res, eager_res) {
        (Ok(a), Ok(b)) => if a.nrows == b.nrows and arrow_sum(a, "sx") == arrow_sum(b, "sx") and arrow_sum(a, "sx") == 20 {
          0
        } else {
          1
        },
        (_, _) => 1,
      }
    },
  }
}

# CSV scan end-to-end through the plan API.
fn test_scan_csv_collect() -> [fs_read, fs_write] Int {
  let path := "/tmp/lex_frame_test_lazy.csv"
  match fio.write_csv_fast(path, make_arrow_df()) {
    Err(_) => 1,
    Ok(_) => match lazy.collect(lazy.sort_by(lazy.filter_eq_int(lazy.scan_csv(path), "g", 20), "x", false)) {
      Err(_) => 1,
      Ok(df2) => if df2.nrows == 3 and arrow_first(df2, "x") == 6 and arrow_sum(df2, "x") == 13 {
        0
      } else {
        1
      },
    },
  }
}

fn fail_if_nonzero(failures :: Int) -> Int {
  1 / if failures == 0 {
    1
  } else {
    0
  }
}

fn run_all() -> [fs_read, fs_write] Unit {
  let failures := test_collect_matches_eager() + test_filter_survives_later_select() + test_eager_order_would_fail() + test_no_narrowing_keeps_all_cols() + test_group_agg_matches_eager() + test_filter_group_pruned_matches_eager() + test_unknown_col_in_pruned_plan_is_error() + test_legacy_frame_collect() + test_explain_shows_rewrites() + test_scan_parquet_pruned_matches_eager() + test_scan_csv_collect()
  let __lex_discard := fail_if_nonzero(failures)
  ()
}

