import "std.map" as map

import "std.arrow" as arrow

import "./col" as col

import "./frame" as frame

import "./value" as val

fn get_col(df :: frame.DataFrame, name :: Str) -> Option[col.Col] {
  map.get(df.columns, name)
}

# ===== Fast-path reductions =====
#
# When `df.arrow_table` is `Some(t)` (built via `frame.from_arrow_table`
# or `io.read_csv_fast`), these route through arrow's column kernels —
# one Rust call over a flat i64/f64 buffer — instead of walking
# `col.Col` (a List[Value]) in interpreted Lex bytecode. The kernel
# itself is essentially free; the win is per-call, ~50-1000x at
# 1k-1M rows. When `arrow_table` is `None`, we fall back to the
# legacy `col.col_sum` / etc. path so the same fn name works in both
# code shapes; callers don't have to branch.

fn sum_col_fast(df :: frame.DataFrame, name :: Str) -> Option[Int] {
  match df.arrow_table {
    None => match sum_col(df, name) {
      None => None,
      Some(v) => match val.as_int(v) {
        None => None,
        Some(n) => Some(n),
      },
    },
    Some(t) => match arrow.col_sum_int(t, name) {
      Err(_) => None,
      Ok(s) => Some(s),
    },
  }
}

fn mean_col_fast(df :: frame.DataFrame, name :: Str) -> Option[Float] {
  match df.arrow_table {
    None => mean_col(df, name),
    Some(t) => match arrow.col_mean(t, name) {
      Err(_) => None,
      Ok(opt_f) => opt_f,
    },
  }
}

fn min_col_fast(df :: frame.DataFrame, name :: Str) -> Option[Int] {
  match df.arrow_table {
    None => match min_col(df, name) {
      None => None,
      Some(v) => match val.as_int(v) {
        None => None,
        Some(n) => Some(n),
      },
    },
    Some(t) => match arrow.col_min_int(t, name) {
      Err(_) => None,
      Ok(opt_i) => opt_i,
    },
  }
}

fn max_col_fast(df :: frame.DataFrame, name :: Str) -> Option[Int] {
  match df.arrow_table {
    None => match max_col(df, name) {
      None => None,
      Some(v) => match val.as_int(v) {
        None => None,
        Some(n) => Some(n),
      },
    },
    Some(t) => match arrow.col_max_int(t, name) {
      Err(_) => None,
      Ok(opt_i) => opt_i,
    },
  }
}

fn count_non_null_fast(df :: frame.DataFrame, name :: Str) -> Int {
  match df.arrow_table {
    None => count_non_null(df, name),
    Some(t) => match arrow.col_count(t, name) {
      Err(_) => 0,
      Ok(n) => n,
    },
  }
}

fn sum_col(df :: frame.DataFrame, name :: Str) -> Option[val.Value] {
  match get_col(df, name) {
    None => None,
    Some(c) => col.col_sum(c),
  }
}

fn mean_col(df :: frame.DataFrame, name :: Str) -> Option[Float] {
  match get_col(df, name) {
    None => None,
    Some(c) => col.col_mean(c),
  }
}

fn min_col(df :: frame.DataFrame, name :: Str) -> Option[val.Value] {
  match get_col(df, name) {
    None => None,
    Some(c) => col.col_min(c),
  }
}

fn max_col(df :: frame.DataFrame, name :: Str) -> Option[val.Value] {
  match get_col(df, name) {
    None => None,
    Some(c) => col.col_max(c),
  }
}

fn variance_col(df :: frame.DataFrame, name :: Str) -> Option[Float] {
  match get_col(df, name) {
    None => None,
    Some(c) => col.col_variance(c),
  }
}

fn std_col(df :: frame.DataFrame, name :: Str) -> Option[Float] {
  match get_col(df, name) {
    None => None,
    Some(c) => col.col_std(c),
  }
}

fn count_all(df :: frame.DataFrame, name :: Str) -> Int {
  match get_col(df, name) {
    None => 0,
    Some(c) => col.col_len(c),
  }
}

fn count_non_null(df :: frame.DataFrame, name :: Str) -> Int {
  match get_col(df, name) {
    None => 0,
    Some(c) => col.col_non_null_count(c),
  }
}

fn n_distinct(df :: frame.DataFrame, name :: Str) -> Int {
  match get_col(df, name) {
    None => 0,
    Some(c) => col.col_n_distinct(c),
  }
}

