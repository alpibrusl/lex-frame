# Headline bench: read a CSV, run a query op, return the result size.
# Same workload pandas runs in bench/pandas_df_ref.py — apples-to-apples
# wall time including process startup, CSV parse, schema inference,
# query execution, and Lex result-shaping.
#
# Measured against lex 0.9.4 + pandas 3.0.3, 7-sample medians:
#
#   n         op             lex 0.9.4   pandas 3.0.3   ratio
#   100 000   group_by_csv    33 ms       36 ms          within 8%
#   100 000   sort_csv        36 ms       33 ms          within 9%
#   100 000   filter_gt_csv   34 ms       29 ms          pandas 17% faster
#   100 000   sum_x_csv       28 ms       26 ms          within 6%
#   1 000 000 group_by_csv   215 ms      274 ms          lex 1.27x faster
#   1 000 000 sort_csv       257 ms      327 ms          lex 1.27x faster
#   1 000 000 filter_gt_csv  226 ms      266 ms          lex 1.18x faster
#   1 000 000 sum_x_csv      180 ms      256 ms          lex 1.42x faster
#
# At 100k, lex's ~25 ms parse + type-check dominates and the two engines
# are within noise. At 1M (query-dominated) lex beats pandas across the
# board. NB: this is std.df direct — public lex-frame API still goes
# through List[Value] until the wrapper migration (lex-frame#6) lands.
#
# Requires lex >= 0.9.4 (std.arrow + std.df, both shipped in lex-lang
# #428). The full lex-frame migration (#6) rewires every public op
# to this path automatically; this file is the in-source proof point
# once the migration lands.

import "std.list" as list

import "std.arrow" as arrow

import "std.df" as df

# Read CSV, group by 'g', sum(x) + mean(y).
fn group_by_csv(path :: Str) -> [fs_read] Int {
  match arrow.read_csv(path) {
    Err(_) => -1,
    Ok(t) => match df.group_by_agg(t, list.cons("g", []), list.cons(("sum_x", "x", "sum"), list.cons(("mean_y", "y", "mean"), []))) {
      Err(_) => -2,
      Ok(out) => arrow.nrows(out),
    },
  }
}

# Read CSV, sort by 'x' descending.
fn sort_csv(path :: Str) -> [fs_read] Int {
  match arrow.read_csv(path) {
    Err(_) => -1,
    Ok(t) => match df.sort_by(t, "x", false) {
      Err(_) => -2,
      Ok(out) => arrow.nrows(out),
    },
  }
}

# Read CSV, filter rows where x > threshold. Apples-to-apples with
# pandas_df_ref.py requires the harness pass `threshold = n // 2`
# (half the rows kept), matching the pandas side's hardcoded `n // 2`.
fn filter_gt_csv(path :: Str, threshold :: Int) -> [fs_read] Int {
  match arrow.read_csv(path) {
    Err(_) => -1,
    Ok(t) => match df.filter_gt_int(t, "x", threshold) {
      Err(_) => -2,
      Ok(out) => arrow.nrows(out),
    },
  }
}

# Pure-reduction baseline: read CSV, sum the 'x' column.
fn sum_x_csv(path :: Str) -> [fs_read] Int {
  match arrow.read_csv(path) {
    Err(_) => -1,
    Ok(t) => match arrow.col_sum_int(t, "x") {
      Ok(s) => s,
      Err(_) => -2,
    },
  }
}

