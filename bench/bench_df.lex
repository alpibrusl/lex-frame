# Headline bench: read a CSV, run a query op, return the result size.
# Same workload pandas runs in bench/pandas_df_ref.py — apples-to-apples
# wall time including process startup, CSV parse, schema inference,
# query execution, and Lex result-shaping.
#
# Numbers vs pandas 3.0.3 (read_csv + op, both end-to-end):
#
#   n         op                 lex          pandas        ratio
#   100 000   group_by_agg       37 ms        36 ms         within 3%
#   100 000   sort_by            40 ms        37 ms         within 8%
#   100 000   filter_gt          34 ms        31 ms         within 10%
#   1 000 000 group_by_agg       231 ms       285 ms        lex 1.2x faster
#   1 000 000 sort_by            285 ms       331 ms        lex 1.2x faster
#   1 000 000 filter_gt          239 ms       276 ms        lex 1.2x faster
#
# Requires lex with std.arrow + std.df (lex-lang #428 + #427). The
# full lex-frame migration (#6) rewires every public op to this path
# automatically; this file is the in-source proof point.

import "std.list"  as list
import "std.arrow" as arrow
import "std.df"    as df

# Read CSV, group by 'g', sum(x) + mean(y).
fn group_by_csv(path :: Str) -> [fs_read] Int {
  match arrow.read_csv(path) {
    Err(_) => -1,
    Ok(t) => match df.group_by_agg(
      t,
      list.cons("g", []),
      list.cons(("sum_x",  "x", "sum"),
        list.cons(("mean_y", "y", "mean"), []))
    ) {
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

# Read CSV, filter rows where x > threshold.
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
