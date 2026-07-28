import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.arrow" as arrow

import "./value" as val

import "./col" as col

import "./frame" as frame

import "./agg" as agg

import "./provenance" as prov

import "./stats" as stats

# Arrow-backed frames report the arrow schema dtypes
# (int64/float64/utf8) via arrow.col_type; legacy frames report the
# Col variant name. Pre-#19 every arrow column showed "unknown".
fn infer_dtypes(df :: frame.DataFrame) -> List[(Str, Str)] {
  list.map(df.col_names, fn (name :: Str) -> (Str, Str) {
    let dtype := match df.arrow_table {
      Some(t) => match arrow.col_type(t, name) {
        Some(s) => s,
        None => "unknown",
      },
      None => match map.get(df.columns, name) {
        None => "unknown",
        Some(c) => col.col_type_name(c),
      },
    }
    (name, dtype)
  })
}

fn summary(df :: frame.DataFrame) -> Str {
  let dtypes := infer_dtypes(df)
  let n_rows := df.nrows
  let n_cols := list.len(df.col_names)
  let shape_s := str.concat(int.to_str(n_rows), str.concat(" rows x ", str.concat(int.to_str(n_cols), " cols")))
  let cols_s := str.join(list.map(dtypes, fn (p :: (Str, Str)) -> Str {
    let name := match p {
      (a, _) => a,
    }
    let dtype := match p {
      (_, b) => b,
    }
    let nulls := match df.arrow_table {
      Some(_) => df.nrows - agg.count_non_null_fast(df, name),
      None => match map.get(df.columns, name) {
        None => 0,
        Some(c) => col.col_null_count(c),
      },
    }
    str.concat("  ", str.concat(name, str.concat(" (", str.concat(dtype, str.concat(") null=", int.to_str(nulls))))))
  }), "\n")
  let hist_s := prov.render_history(df.provenance)
  str.join([str.concat("Shape: ", shape_s), "Columns:", cols_s, "Provenance:", hist_s], "\n")
}

# Row values live in the legacy columns map — an arrow-backed frame
# renders header + an explicit marker row instead of n rows of
# "null" (pre-#19 behavior).
fn to_markdown(df :: frame.DataFrame, max_rows :: Int) -> Str {
  let n := match df.arrow_table {
    Some(_) => 0,
    None => if max_rows < df.nrows {
      max_rows
    } else {
      df.nrows
    },
  }
  let cols := df.col_names
  let hdr := str.concat("| ", str.concat(str.join(cols, " | "), " |"))
  let sep := str.concat("| ", str.concat(str.join(list.map(cols, fn (_nm :: Str) -> Str {
    "---"
  }), " | "), " |"))
  let marker := match df.arrow_table {
    Some(_) => ["_(arrow-backed frame: values not materialized — export via io.write_csv_fast, or reduce via agg.*_fast)_"],
    None => [],
  }
  let rows := list.map(frame.range_list(0, n), fn (i :: Int) -> Str {
    let vals := list.map(cols, fn (name :: Str) -> Str {
      match map.get(df.columns, name) {
        None => "null",
        Some(c) => val.to_str(frame.nth_value(c, i)),
      }
    })
    str.concat("| ", str.concat(str.join(vals, " | "), " |"))
  })
  str.join(list.cons(hdr, list.cons(sep, list.concat(marker, rows))), "\n")
}

# Same marker treatment as to_markdown: arrow-backed frames emit
# schema + a "note" key + empty rows instead of rows of nulls.
fn to_json_payload(df :: frame.DataFrame, max_rows :: Int) -> Str {
  let n := match df.arrow_table {
    Some(_) => 0,
    None => if max_rows < df.nrows {
      max_rows
    } else {
      df.nrows
    },
  }
  let dtypes := infer_dtypes(df)
  let schema_entries := list.map(dtypes, fn (p :: (Str, Str)) -> Str {
    let name := match p {
      (a, _) => a,
    }
    let dtype := match p {
      (_, b) => b,
    }
    str.concat("\"", str.concat(name, str.concat("\": \"", str.concat(dtype, "\""))))
  })
  let schema_s := str.concat("{\"schema\": {\"columns\": {", str.concat(str.join(schema_entries, ", "), str.concat("}, \"shape\": [", str.concat(int.to_str(df.nrows), str.concat(", ", str.concat(int.to_str(list.len(df.col_names)), "]}"))))))
  let rows_s := list.map(frame.range_list(0, n), fn (i :: Int) -> Str {
    let pairs := list.map(df.col_names, fn (name :: Str) -> Str {
      let v := match map.get(df.columns, name) {
        None => val.vnull(),
        Some(c) => frame.nth_value(c, i),
      }
      str.concat("\"", str.concat(name, str.concat("\": ", json_val(v))))
    })
    str.concat("{", str.concat(str.join(pairs, ", "), "}"))
  })
  let note_s := match df.arrow_table {
    Some(_) => ", \"note\": \"arrow-backed frame: rows not materialized — export via io.write_csv_fast or reduce via agg.*_fast\"",
    None => "",
  }
  str.concat(schema_s, str.concat(note_s, str.concat(", \"rows\": [", str.concat(str.join(rows_s, ", "), "]}"))))
}

fn json_val(v :: val.Value) -> Str {
  let t := val.type_name(v)
  if t == "Null" {
    "null"
  } else {
    if t == "Bool" or t == "Int" or t == "Float" {
      val.to_str(v)
    } else {
      str.concat("\"", str.concat(val.to_str(v), "\""))
    }
  }
}

# Arrow-backed frames build the profile from the arrow kernels
# (dtype via col_type, counts via col_count, mean/min/max via the
# reduction kernels — min/max are int-only, "n/a" otherwise; std and
# distinct have no kernel yet). Pre-#19 this returned "" on arrow.
fn column_profile(df :: frame.DataFrame, column :: Str) -> Str {
  match df.arrow_table {
    Some(t) => match arrow.col_type(t, column) {
      None => "",
      Some(dtype) => {
        let n := df.nrows
        let non_null := agg.count_non_null_fast(df, column)
        let null_cnt := n - non_null
        let base := str.join([str.concat("column:   ", column), str.concat("dtype:    ", dtype), str.concat("count:    ", int.to_str(n)), str.concat("non-null: ", int.to_str(non_null)), str.concat("null:     ", int.to_str(null_cnt)), "distinct: n/a (no arrow kernel)"], "\n")
        let mean_s := match agg.mean_col_fast(df, column) {
          Some(x) => float.to_str(x),
          None => "n/a",
        }
        let min_s := match agg.min_col_fast(df, column) {
          Some(x) => int.to_str(x),
          None => "n/a",
        }
        let max_s := match agg.max_col_fast(df, column) {
          Some(x) => int.to_str(x),
          None => "n/a",
        }
        if dtype == "int64" or dtype == "Int64" or dtype == "float64" or dtype == "Float64" {
          str.concat(base, str.concat("\n", str.join([str.concat("mean:     ", mean_s), "std:      n/a (no arrow kernel)", str.concat("min:      ", min_s), str.concat("max:      ", max_s)], "\n")))
        } else {
          base
        }
      },
    },
    None => column_profile_legacy(df, column),
  }
}

fn column_profile_legacy(df :: frame.DataFrame, column :: Str) -> Str {
  match map.get(df.columns, column) {
    None => "",
    Some(c) => {
      let tmp := match frame.from_typed_columns([(column, c)]) {
        Ok(d) => d,
        Err(_) => frame.empty(),
      }
      let dtype := col.col_type_name(c)
      let n := col.col_len(c)
      let null_cnt := col.col_null_count(c)
      let non_null := n - null_cnt
      let distinct := agg.n_distinct(tmp, column)
      let base := str.join([str.concat("column:   ", column), str.concat("dtype:    ", dtype), str.concat("count:    ", int.to_str(n)), str.concat("non-null: ", int.to_str(non_null)), str.concat("null:     ", int.to_str(null_cnt)), str.concat("distinct: ", int.to_str(distinct))], "\n")
      let is_numeric := dtype == "Int" or dtype == "Float" or dtype == "Int?" or dtype == "Float?"
      let numeric_s := if is_numeric {
        let mean_s := match agg.mean_col(tmp, column) {
          Some(x) => float.to_str(x),
          None => "n/a",
        }
        let std_s := match agg.std_col(tmp, column) {
          Some(x) => float.to_str(x),
          None => "n/a",
        }
        let min_s := match agg.min_col(tmp, column) {
          Some(v) => val.to_str(v),
          None => "n/a",
        }
        let max_s := match agg.max_col(tmp, column) {
          Some(v) => val.to_str(v),
          None => "n/a",
        }
        str.join([str.concat("mean:     ", mean_s), str.concat("std:      ", std_s), str.concat("min:      ", min_s), str.concat("max:      ", max_s)], "\n")
      } else {
        ""
      }
      if str.is_empty(numeric_s) {
        base
      } else {
        str.concat(base, str.concat("\n", numeric_s))
      }
    },
  }
}

fn history(df :: frame.DataFrame) -> Str {
  prov.render_history(df.provenance)
}

# On arrow-backed frames sampling is the first n rows via the
# zero-copy head kernel (no stride kernel yet); legacy frames keep
# the evenly-strided pick. Pre-#19 arrow frames sampled empty rows.
fn sample_rows(df :: frame.DataFrame, n :: Int) -> frame.DataFrame {
  match df.arrow_table {
    Some(_) => frame.head(df, if n < 0 {
      0
    } else {
      n
    }),
    None => {
      let actual := if n < df.nrows {
        n
      } else {
        df.nrows
      }
      if actual <= 0 {
        frame.empty()
      } else {
        if actual >= df.nrows {
          df
        } else {
          let step := df.nrows / actual
          let indices := list.map(frame.range_list(0, actual), fn (i :: Int) -> Int {
            i * step
          })
          frame.pick_rows(df, indices)
        }
      }
    },
  }
}

fn null_report(df :: frame.DataFrame) -> frame.DataFrame {
  let n := df.nrows
  let col_vals := list.map(df.col_names, fn (nm :: Str) -> val.Value {
    val.vstr(nm)
  })
  let count_vals := list.map(df.col_names, fn (nm :: Str) -> val.Value {
    match df.arrow_table {
      Some(_) => val.vint(df.nrows - agg.count_non_null_fast(df, nm)),
      None => match map.get(df.columns, nm) {
        None => val.vnull(),
        Some(c) => val.vint(col.col_null_count(c)),
      },
    }
  })
  let pct_vals := list.map(count_vals, fn (v :: val.Value) -> val.Value {
    match val.as_int(v) {
      None => val.vnull(),
      Some(c) => if n == 0 {
        val.vfloat(0.0)
      } else {
        val.vfloat(int.to_float(c) / int.to_float(n) * 100.0)
      },
    }
  })
  match frame.from_columns([("column", col_vals), ("null_count", count_vals), ("null_pct", pct_vals)]) {
    Ok(d) => d,
    Err(_) => frame.empty(),
  }
}

