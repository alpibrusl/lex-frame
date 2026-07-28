import "std.list" as list

import "../src/frame" as frame

import "../src/select" as sel

import "../src/sort" as srt

import "../src/group" as grp

import "../src/lazy" as lazy

import "../src/io" as fio

# Lazy-vs-eager benchmark (lex-frame#16). Every pair computes the
# same result through the same kernels; the delta is what the plan
# rewrites (filter hoisting + projection pruning) buy. Run each case
# via:
#   lex run --allow-effects fs_read,fs_write bench/bench_lazy.lex <case> <args>
# Numeric pipeline, eager: read all cols -> filter -> sort -> group.
fn pipeline_eager(path :: Str, threshold :: Int) -> [fs_read] Int {
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

# Same pipeline as a plan: the group_agg node narrows, so the source
# is pruned to [x,g] right after the read (drops y).
fn pipeline_lazy(path :: Str, threshold :: Int) -> [fs_read] Int {
  let plan := lazy.group_agg(lazy.sort_by(lazy.filter_gt_int(lazy.scan_csv(path), "x", threshold), "x", false), ["g"], list.cons(grp.agg_spec("sum_x", "x", grp.agg_sum()), []))
  match lazy.collect(plan) {
    Err(_) => -1,
    Ok(out) => out.nrows,
  }
}

# H2O db-benchmark q2 (sum v1 by id1, id2), eager on CSV.
fn q2_eager(path :: Str) -> [fs_read] Int {
  match fio.read_csv_fast(path) {
    Err(_) => -1,
    Ok(df) => match grp.group_agg_by_keys_fast(df, list.cons("id1", ["id2"]), [grp.agg_spec("v1_sum", "v1", grp.agg_sum())]) {
      Err(_) => -2,
      Ok(out) => out.nrows,
    },
  }
}

# q2 as a plan on CSV: pruned to [id1,id2,v1] right after the read —
# the 6 untouched columns leave the pipeline immediately.
fn q2_lazy(path :: Str) -> [fs_read] Int {
  match lazy.collect(lazy.group_agg(lazy.scan_csv(path), list.cons("id1", ["id2"]), [grp.agg_spec("v1_sum", "v1", grp.agg_sum())])) {
    Err(_) => -1,
    Ok(out) => out.nrows,
  }
}

# One-time prep: materialize the H2O CSV as parquet for the
# q2_parquet_* cases.
fn prep_parquet(src :: Str, dst :: Str) -> [fs_read, fs_write] Int {
  match fio.read_csv_fast(src) {
    Err(_) => -1,
    Ok(df) => match fio.write_parquet(dst, df) {
      Err(_) => -2,
      Ok(_) => df.nrows,
    },
  }
}

# q2 eager on parquet: full-width read (all 9 columns decoded).
fn q2_parquet_eager(path :: Str) -> [fs_read] Int {
  match fio.read_parquet(path) {
    Err(_) => -1,
    Ok(df) => match grp.group_agg_by_keys_fast(df, list.cons("id1", ["id2"]), [grp.agg_spec("v1_sum", "v1", grp.agg_sum())]) {
      Err(_) => -2,
      Ok(out) => out.nrows,
    },
  }
}

# q2 lazy on parquet: the projection is pushed into the parquet
# reader itself (read_parquet_cols) — only id1, id2, v1 are decoded
# (lex-frame#17).
fn q2_parquet_lazy(path :: Str) -> [fs_read] Int {
  match lazy.collect(lazy.group_agg(lazy.scan_parquet(path), list.cons("id1", ["id2"]), [grp.agg_spec("v1_sum", "v1", grp.agg_sum())])) {
    Err(_) => -1,
    Ok(out) => out.nrows,
  }
}

