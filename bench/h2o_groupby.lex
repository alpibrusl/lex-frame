# H2O.ai db-benchmark groupby queries (G1 table) through the PUBLIC
# lex-frame fast API — the suite pandas / Polars / DuckDB / data.table
# report against. Dataset: bench/gen_h2o_csv.py (same schema and
# cardinalities as the official generator). Each fn reads the CSV
# fresh and returns the result's row count, mirroring the accounting
# in bench_frame_fast.lex.
#
# Query numbering follows the official suite. q1/q2/q3/q4/q5 are the
# ones the current agg kernel set (sum/mean/min/max/count/n_distinct)
# covers; the advanced queries (q6 median, q8 top-2 windows, q9
# regression, q10 sum+count by 6 keys) need kernels lex-lang doesn't
# ship yet.
#
#   lex run --allow-effects fs_read,fs_write,io bench/h2o_groupby.lex q1 '"/tmp/h2o_g1_1e6.csv"'

import "std.list" as list

import "../src/group" as grp

import "../src/io" as fio

fn run_groupby(path :: Str, keys :: List[Str], specs :: List[grp.AggSpec]) -> [fs_read] Int {
  match fio.read_csv_fast(path) {
    Err(_) => -1,
    Ok(df) => match grp.group_agg_by_keys_fast(df, keys, specs) {
      Err(_) => -2,
      Ok(out) => out.nrows,
    },
  }
}

# q1: sum v1 by id1 (100 groups)
fn q1(path :: Str) -> [fs_read] Int {
  run_groupby(path, ["id1"], [grp.agg_spec("v1_sum", "v1", grp.agg_sum())])
}

# q2: sum v1 by id1:id2 (10k groups)
fn q2(path :: Str) -> [fs_read] Int {
  run_groupby(path, list.cons("id1", ["id2"]), [grp.agg_spec("v1_sum", "v1", grp.agg_sum())])
}

# q3: sum v1, mean v3 by id3 (N/K groups — high cardinality)
fn q3(path :: Str) -> [fs_read] Int {
  run_groupby(path, ["id3"], list.cons(grp.agg_spec("v1_sum", "v1", grp.agg_sum()), [grp.agg_spec("v3_mean", "v3", grp.agg_mean())]))
}

# q4: mean v1, v2, v3 by id4 (100 groups)
fn q4(path :: Str) -> [fs_read] Int {
  run_groupby(path, ["id4"], list.cons(grp.agg_spec("v1_mean", "v1", grp.agg_mean()), list.cons(grp.agg_spec("v2_mean", "v2", grp.agg_mean()), [grp.agg_spec("v3_mean", "v3", grp.agg_mean())])))
}

# q5: sum v1, v2, v3 by id6 (N/K groups — high cardinality)
fn q5(path :: Str) -> [fs_read] Int {
  run_groupby(path, ["id6"], list.cons(grp.agg_spec("v1_sum", "v1", grp.agg_sum()), list.cons(grp.agg_spec("v2_sum", "v2", grp.agg_sum()), [grp.agg_spec("v3_sum", "v3", grp.agg_sum())])))
}

# q7: max v1 - min v2 by id3. The subtraction needs a derived column,
# which the fast path can't express yet — this runs the max/min half
# so the group cost is still measured; the difference op is the gap.
fn q7_partial(path :: Str) -> [fs_read] Int {
  run_groupby(path, ["id3"], list.cons(grp.agg_spec("v1_max", "v1", grp.agg_max()), [grp.agg_spec("v2_min", "v2", grp.agg_min())]))
}

