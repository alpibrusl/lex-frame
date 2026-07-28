import "std.list" as list

import "std.str" as str

import "std.map" as map

import "std.int" as int

import "std.float" as float

import "std.arrow" as arrow

import "std.df" as dfq

import "./value" as val

import "./col" as col

import "./frame" as frame

import "./provenance" as prov

fn row_get_or_null(row :: List[(Str, val.Value)], name :: Str) -> val.Value {
  match list.fold(row, None, fn (acc :: Option[(Str, val.Value)], pair :: (Str, val.Value)) -> Option[(Str, val.Value)] {
    match acc {
      Some(_) => acc,
      None => if match pair {
        (k, _) => k == name,
      } {
        Some(pair)
      } else {
        None
      },
    }
  }) {
    None => val.vnull(),
    Some(p) => match p {
      (_, v) => v,
    },
  }
}

fn row_get(row :: List[(Str, val.Value)], name :: Str) -> Option[val.Value] {
  match list.fold(row, None, fn (acc :: Option[(Str, val.Value)], pair :: (Str, val.Value)) -> Option[(Str, val.Value)] {
    match acc {
      Some(_) => acc,
      None => if match pair {
        (k, _) => k == name,
      } {
        Some(pair)
      } else {
        None
      },
    }
  }) {
    None => None,
    Some(p) => match p {
      (_, v) => Some(v),
    },
  }
}

fn select_cols(df :: frame.DataFrame, wanted :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let missing := list.filter(wanted, fn (name :: Str) -> Bool {
    list.fold(df.col_names, true, fn (acc :: Bool, n :: Str) -> Bool {
      acc and n != name
    })
  })
  if list.is_empty(missing) {
    let new_map := list.fold(wanted, map.new(), fn (acc :: Map[Str, col.Col], name :: Str) -> Map[Str, col.Col] {
      match map.get(df.columns, name) {
        None => acc,
        Some(c) => map.set(acc, name, c),
      }
    })
    Ok({ col_names: wanted, columns: new_map, nrows: df.nrows, provenance: list.cons(prov.op_select(wanted), df.provenance), arrow_table: None })
  } else {
    let first := match list.head(missing) {
      Some(n) => n,
      None => "",
    }
    Err(frame.frame_err("SELECT_UNKNOWN_COLUMN", str.concat("column '", str.concat(first, "' not found")), first))
  }
}

# Arrow-aware projection. The legacy `select_cols` above always
# returns a list-backed frame (arrow_table: None) — calling it on an
# arrow-backed frame silently drops the columnar backing and, because
# the legacy `columns` map is empty on arrow frames, drops the data
# with it. This variant keeps each backing on its own path:
# arrow-backed frames project through `arrow.select_cols` (zero-copy
# column slice), list-backed frames use the legacy path.
fn select_cols_fast(df :: frame.DataFrame, wanted :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  match df.arrow_table {
    None => select_cols(df, wanted),
    Some(t) => match arrow.select_cols(t, wanted) {
      Err(e) => Err(frame.frame_err("SELECT_UNKNOWN_COLUMN", e, str.join(wanted, ","))),
      Ok(t2) => Ok(frame.with_arrow_table(df, t2, prov.op_select(wanted))),
    },
  }
}

fn drop_cols(df :: frame.DataFrame, to_drop :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let keep := list.filter(df.col_names, fn (name :: Str) -> Bool {
    list.fold(to_drop, true, fn (acc :: Bool, d :: Str) -> Bool {
      acc and d != name
    })
  })
  select_cols(df, keep)
}

fn rename_col(df :: frame.DataFrame, old_name :: Str, new_name :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  let missing := list.fold(df.col_names, true, fn (acc :: Bool, n :: Str) -> Bool {
    acc and n != old_name
  })
  if missing {
    Err(frame.frame_err("FRAME_COLUMN_NOT_FOUND", str.concat("column '", str.concat(old_name, "' not found")), old_name))
  } else {
    let new_names := list.map(df.col_names, fn (n :: Str) -> Str {
      if n == old_name {
        new_name
      } else {
        n
      }
    })
    let old_col := match map.get(df.columns, old_name) {
      Some(c) => c,
      None => col.col_str([]),
    }
    let new_map := map.set(df.columns, new_name, old_col)
    Ok({ col_names: new_names, columns: new_map, nrows: df.nrows, provenance: list.cons(prov.op_rename(old_name, new_name), df.provenance), arrow_table: None })
  }
}

fn filter_rows(df :: frame.DataFrame, pred_desc :: Str, pred :: (List[(Str, val.Value)]) -> Bool) -> Result[frame.DataFrame, frame.FrameError] {
  let kept := list.filter(frame.range_list(0, df.nrows), fn (i :: Int) -> Bool {
    pred(frame.get_row(df, i))
  })
  let df2 := frame.pick_rows(df, kept)
  Ok({ col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows, provenance: list.cons(prov.op_filter(pred_desc, df2.nrows), df.provenance), arrow_table: None })
}

# Shared shape for the fast filters below: arrow-backed frames route
# to the named std.df kernel; list-backed frames fall back to
# filter_rows with an equivalent predicate.
fn wrap_df_filter(df :: frame.DataFrame, name :: Str, desc :: Str, filtered :: Result[Table, Str]) -> Result[frame.DataFrame, frame.FrameError] {
  match filtered {
    Err(e) => Err(frame.frame_err("SELECT_UNKNOWN_COLUMN", e, name)),
    Ok(t2) => Ok(frame.with_arrow_table(df, t2, prov.op_filter(desc, arrow.nrows(t2)))),
  }
}

# ===== Fast-path filters =====
#
# When `df.arrow_table` is `Some(t)`, these route through std.df's
# Polars-backed filter kernels — one Rust call over the columnar
# buffer — instead of materialising every row as a List[(Str, Value)]
# and running the predicate closure in interpreted bytecode (the
# legacy `filter_rows` path is O(n^2) on the linked-list row API).
# When `arrow_table` is `None`, they fall back to `filter_rows` with
# an equivalent predicate, so the same call works on both backings.
fn filter_eq_int_fast(df :: frame.DataFrame, name :: Str, v :: Int) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, str.concat(" == ", int.to_str(v)))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      match val.as_int(row_get_or_null(row, name)) {
        None => false,
        Some(n) => n == v,
      }
    }),
    Some(t) => match dfq.filter_eq_int(t, name, v) {
      Err(e) => Err(frame.frame_err("SELECT_UNKNOWN_COLUMN", e, name)),
      Ok(t2) => Ok(frame.with_arrow_table(df, t2, prov.op_filter(desc, arrow.nrows(t2)))),
    },
  }
}

fn filter_gt_int_fast(df :: frame.DataFrame, name :: Str, v :: Int) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, str.concat(" > ", int.to_str(v)))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      match val.as_int(row_get_or_null(row, name)) {
        None => false,
        Some(n) => n > v,
      }
    }),
    Some(t) => match dfq.filter_gt_int(t, name, v) {
      Err(e) => Err(frame.frame_err("SELECT_UNKNOWN_COLUMN", e, name)),
      Ok(t2) => Ok(frame.with_arrow_table(df, t2, prov.op_filter(desc, arrow.nrows(t2)))),
    },
  }
}

fn filter_lt_int_fast(df :: frame.DataFrame, name :: Str, v :: Int) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, str.concat(" < ", int.to_str(v)))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      match val.as_int(row_get_or_null(row, name)) {
        None => false,
        Some(n) => n < v,
      }
    }),
    Some(t) => match dfq.filter_lt_int(t, name, v) {
      Err(e) => Err(frame.frame_err("SELECT_UNKNOWN_COLUMN", e, name)),
      Ok(t2) => Ok(frame.with_arrow_table(df, t2, prov.op_filter(desc, arrow.nrows(t2)))),
    },
  }
}

fn filter_eq_str_fast(df :: frame.DataFrame, name :: Str, v :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, str.concat(" == \"", str.concat(v, "\"")))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      match val.as_str(row_get_or_null(row, name)) {
        None => false,
        Some(s) => s == v,
      }
    }),
    Some(t) => match dfq.filter_eq_str(t, name, v) {
      Err(e) => Err(frame.frame_err("SELECT_UNKNOWN_COLUMN", e, name)),
      Ok(t2) => Ok(frame.with_arrow_table(df, t2, prov.op_filter(desc, arrow.nrows(t2)))),
    },
  }
}

fn filter_eq_float_fast(df :: frame.DataFrame, name :: Str, v :: Float) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, str.concat(" == ", float.to_str(v)))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      match val.as_float(row_get_or_null(row, name)) {
        None => false,
        Some(f) => f == v,
      }
    }),
    Some(t) => wrap_df_filter(df, name, desc, dfq.filter_eq_float(t, name, v)),
  }
}

fn filter_gt_float_fast(df :: frame.DataFrame, name :: Str, v :: Float) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, str.concat(" > ", float.to_str(v)))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      match val.as_float(row_get_or_null(row, name)) {
        None => false,
        Some(f) => f > v,
      }
    }),
    Some(t) => wrap_df_filter(df, name, desc, dfq.filter_gt_float(t, name, v)),
  }
}

fn filter_lt_float_fast(df :: frame.DataFrame, name :: Str, v :: Float) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, str.concat(" < ", float.to_str(v)))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      match val.as_float(row_get_or_null(row, name)) {
        None => false,
        Some(f) => f < v,
      }
    }),
    Some(t) => wrap_df_filter(df, name, desc, dfq.filter_lt_float(t, name, v)),
  }
}

# Membership filter: keep rows whose `name` value is one of `vs`.
fn filter_in_str_fast(df :: frame.DataFrame, name :: Str, vs :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, str.concat(" in [", str.concat(str.join(vs, ","), "]")))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      match val.as_str(row_get_or_null(row, name)) {
        None => false,
        Some(s) => list.fold(vs, false, fn (acc :: Bool, cand :: Str) -> Bool {
          acc or cand == s
        }),
      }
    }),
    Some(t) => wrap_df_filter(df, name, desc, dfq.filter_in_str(t, name, vs)),
  }
}

# Null-handling filters. On arrow-backed frames nulls come from CSV
# gaps or unmatched left-join rows; on legacy frames from val.vnull().
fn filter_isnull_fast(df :: frame.DataFrame, name :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, " is null")
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      val.is_null(row_get_or_null(row, name))
    }),
    Some(t) => wrap_df_filter(df, name, desc, dfq.filter_isnull(t, name)),
  }
}

fn filter_notnull_fast(df :: frame.DataFrame, name :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat(name, " is not null")
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      if val.is_null(row_get_or_null(row, name)) {
        false
      } else {
        true
      }
    }),
    Some(t) => wrap_df_filter(df, name, desc, dfq.filter_notnull(t, name)),
  }
}

# Drop every row that has a null in ANY of the named columns.
fn drop_nulls_fast(df :: frame.DataFrame, cols :: List[Str]) -> Result[frame.DataFrame, frame.FrameError] {
  let desc := str.concat("drop_nulls [", str.concat(str.join(cols, ","), "]"))
  match df.arrow_table {
    None => filter_rows(df, desc, fn (row :: List[(Str, val.Value)]) -> Bool {
      list.fold(cols, true, fn (acc :: Bool, c :: Str) -> Bool {
        acc and if val.is_null(row_get_or_null(row, c)) {
          false
        } else {
          true
        }
      })
    }),
    Some(t) => wrap_df_filter(df, str.join(cols, ","), desc, dfq.drop_nulls(t, cols)),
  }
}

fn with_column(df :: frame.DataFrame, name :: Str, derive :: (List[(Str, val.Value)]) -> val.Value) -> Result[frame.DataFrame, frame.FrameError] {
  let new_vals := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> val.Value {
    derive(frame.get_row(df, i))
  })
  frame.add_column(df, name, new_vals)
}

