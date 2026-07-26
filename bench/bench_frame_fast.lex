# Same headline workload as bench_df.lex (read CSV, one query op,
# return result size) — but through the PUBLIC lex-frame API
# (io.read_csv_fast + the `_fast` ops), not std.df directly. The
# delta between this file and bench_df.lex is the cost of the
# lex-frame wrapper layer: provenance recording, FrameError mapping,
# and the DataFrame record round-trip per op. Measured at ~1-2 ms
# per op on 1M rows — the wrapper is effectively free; see
# bench/REPORT.md ("public API on the fast path").

import "std.list" as list

import "../src/frame" as frame

import "../src/select" as sel

import "../src/sort" as srt

import "../src/group" as grp

import "../src/io" as fio

# Read CSV, group by 'g', sum(x) + mean(y). Result: number of groups.
fn group_by_csv(path :: Str) -> [fs_read] Int {
  match fio.read_csv_fast(path) {
    Err(_) => -1,
    Ok(df) => {
      let specs := list.cons(grp.agg_spec("sum_x", "x", grp.agg_sum()), list.cons(grp.agg_spec("mean_y", "y", grp.agg_mean()), []))
      match grp.group_agg_fast(df, "g", specs) {
        Err(_) => -2,
        Ok(out) => out.nrows,
      }
    },
  }
}

# Read CSV, sort by 'x' descending.
fn sort_csv(path :: Str) -> [fs_read] Int {
  match fio.read_csv_fast(path) {
    Err(_) => -1,
    Ok(df) => srt.sort_by_fast(df, "x", false).nrows,
  }
}

# Read CSV, filter rows where x > threshold (pass n/2 to keep half,
# matching bench_df.lex / pandas_df_ref.py).
fn filter_gt_csv(path :: Str, threshold :: Int) -> [fs_read] Int {
  match fio.read_csv_fast(path) {
    Err(_) => -1,
    Ok(df) => match sel.filter_gt_int_fast(df, "x", threshold) {
      Err(_) => -2,
      Ok(out) => out.nrows,
    },
  }
}

# Pure-reduction baseline: read CSV, sum the 'x' column.
import "../src/agg" as agg

fn sum_x_csv(path :: Str) -> [fs_read] Int {
  match fio.read_csv_fast(path) {
    Err(_) => -1,
    Ok(df) => match agg.sum_col_fast(df, "x") {
      Some(s) => s,
      None => -2,
    },
  }
}

# Full pipeline: filter half, sort, group — everything stays
# arrow-backed between ops. Result: number of groups.
fn pipeline_csv(path :: Str, threshold :: Int) -> [fs_read] Int {
  match fio.read_csv_fast(path) {
    Err(_) => -1,
    Ok(df) => match sel.filter_gt_int_fast(df, "x", threshold) {
      Err(_) => -2,
      Ok(hot) => {
        let ranked := srt.sort_by_fast(hot, "x", false)
        match grp.group_agg_fast(ranked, "g", list.cons(grp.agg_spec("sum_x", "x", grp.agg_sum()), [])) {
          Err(_) => -3,
          Ok(out) => out.nrows,
        }
      },
    },
  }
}

