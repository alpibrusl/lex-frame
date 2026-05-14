# lex-frame — column aggregations
#
# Thin wrappers over col.* typed aggregations.
# All heavy lifting (type dispatch, null handling) lives in col.lex.

import "std.map" as map
import "./col"   as col
import "./frame" as frame
import "./value" as val

fn get_col(df :: frame.DataFrame, name :: Str) -> Option[col.Col] {
  map.get(df.columns, name)
}

fn sum_col(df :: frame.DataFrame, name :: Str) -> Option[val.Value] {
  match get_col(df, name) {
    None    => None,
    Some(c) => col.col_sum(c),
  }
}

fn mean_col(df :: frame.DataFrame, name :: Str) -> Option[Float] {
  match get_col(df, name) {
    None    => None,
    Some(c) => col.col_mean(c),
  }
}

fn min_col(df :: frame.DataFrame, name :: Str) -> Option[val.Value] {
  match get_col(df, name) {
    None    => None,
    Some(c) => col.col_min(c),
  }
}

fn max_col(df :: frame.DataFrame, name :: Str) -> Option[val.Value] {
  match get_col(df, name) {
    None    => None,
    Some(c) => col.col_max(c),
  }
}

fn variance_col(df :: frame.DataFrame, name :: Str) -> Option[Float] {
  match get_col(df, name) {
    None    => None,
    Some(c) => col.col_variance(c),
  }
}

fn std_col(df :: frame.DataFrame, name :: Str) -> Option[Float] {
  match get_col(df, name) {
    None    => None,
    Some(c) => col.col_std(c),
  }
}

fn count_all(df :: frame.DataFrame, name :: Str) -> Int {
  match get_col(df, name) {
    None    => 0,
    Some(c) => col.col_len(c),
  }
}

fn count_non_null(df :: frame.DataFrame, name :: Str) -> Int {
  match get_col(df, name) {
    None    => 0,
    Some(c) => col.col_non_null_count(c),
  }
}

fn n_distinct(df :: frame.DataFrame, name :: Str) -> Int {
  match get_col(df, name) {
    None    => 0,
    Some(c) => col.col_n_distinct(c),
  }
}
