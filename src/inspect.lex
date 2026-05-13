import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.int" as int

import "std.float" as float

import "./value" as val

import "./frame" as frame

import "./agg" as agg

import "./provenance" as prov

import "./stats" as stats

fn infer_dtypes(df :: frame.DataFrame) -> List[(Str, Str)] {
  list.map(df.col_names, fn (name :: Str) -> (Str, Str) {
    let dtype := match map.get(df.columns, name) {
      None => "unknown",
      Some(xs) => dominant_type(xs),
    }
    (name, dtype)
  })
}

fn dominant_type(col :: List[val.Value]) -> Str {
  let non_null := list.filter(col, fn (v :: val.Value) -> Bool {
    if val.is_null(v) {
      false
    } else {
      true
    }
  })
  if list.is_empty(non_null) {
    "null"
  } else {
    let counts := list.fold(non_null, map.new(), fn (m :: Map[Str, Int], v :: val.Value) -> Map[Str, Int] {
      let t := val.type_name(v)
      let c := match map.get(m, t) {
        Some(n) => n,
        None => 0,
      }
      map.set(m, t, c + 1)
    })
    list.fold(map.entries(counts), "unknown", fn (best :: Str, pair :: (Str, Int)) -> Str {
      let t := match pair {
        (a, _) => a,
      }
      let c := match pair {
        (_, b) => b,
      }
      match map.get(counts, best) {
        None => t,
        Some(bc) => if c > bc {
          t
        } else {
          best
        },
      }
    })
  }
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
    let nulls := match map.get(df.columns, name) {
      None => 0,
      Some(xs) => list.len(list.filter(xs, fn (v :: val.Value) -> Bool {
        val.is_null(v)
      })),
    }
    str.concat("  ", str.concat(name, str.concat(" (", str.concat(dtype, str.concat(") null=", int.to_str(nulls))))))
  }), "\n")
  let hist_s := prov.render_history(df.provenance)
  str.join([str.concat("Shape: ", shape_s), "Columns:", cols_s, "Provenance:", hist_s], "\n")
}

fn to_markdown(df :: frame.DataFrame, max_rows :: Int) -> Str {
  let n := if max_rows < df.nrows {
    max_rows
  } else {
    df.nrows
  }
  let cols := df.col_names
  let hdr := str.concat("| ", str.concat(str.join(cols, " | "), " |"))
  let sep := str.concat("| ", str.concat(str.join(list.map(cols, fn (_nm :: Str) -> Str {
    "---"
  }), " | "), " |"))
  let rows := list.map(frame.range_list(0, n), fn (i :: Int) -> Str {
    let vals := list.map(cols, fn (name :: Str) -> Str {
      match map.get(df.columns, name) {
        None => "null",
        Some(col) => val.to_str(frame.nth_value(col, i)),
      }
    })
    str.concat("| ", str.concat(str.join(vals, " | "), " |"))
  })
  str.join(list.cons(hdr, list.cons(sep, rows)), "\n")
}

fn to_json_payload(df :: frame.DataFrame, max_rows :: Int) -> Str {
  let n := if max_rows < df.nrows {
    max_rows
  } else {
    df.nrows
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
        Some(col) => frame.nth_value(col, i),
      }
      str.concat("\"", str.concat(name, str.concat("\": ", json_val(v))))
    })
    str.concat("{", str.concat(str.join(pairs, ", "), "}"))
  })
  str.concat(schema_s, str.concat(", \"rows\": [", str.concat(str.join(rows_s, ", "), "]}")))
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

fn column_profile(df :: frame.DataFrame, col :: Str) -> Str {
  match map.get(df.columns, col) {
    None => "",
    Some(xs) => {
      let tmp := match frame.from_columns([(col, xs)]) {
        Ok(d) => d,
        Err(_) => frame.empty(),
      }
      let dtype := dominant_type(xs)
      let n := list.len(xs)
      let null_cnt := list.len(list.filter(xs, fn (v :: val.Value) -> Bool {
        val.is_null(v)
      }))
      let non_null := n - null_cnt
      let distinct := agg.n_distinct(tmp, col)
      let base := str.join([str.concat("column:   ", col), str.concat("dtype:    ", dtype), str.concat("count:    ", int.to_str(n)), str.concat("non-null: ", int.to_str(non_null)), str.concat("null:     ", int.to_str(null_cnt)), str.concat("distinct: ", int.to_str(distinct))], "\n")
      let is_numeric := dtype == "Int" or dtype == "Float"
      let numeric_s := if is_numeric {
        let mean_s := match agg.mean_col(tmp, col) {
          Some(x) => float.to_str(x),
          None => "n/a",
        }
        let std_s := match agg.std_col(tmp, col) {
          Some(x) => float.to_str(x),
          None => "n/a",
        }
        let min_s := match agg.min_col(tmp, col) {
          Some(v) => val.to_str(v),
          None => "n/a",
        }
        let max_s := match agg.max_col(tmp, col) {
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

fn sample_rows(df :: frame.DataFrame, n :: Int) -> frame.DataFrame {
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
}

fn null_report(df :: frame.DataFrame) -> frame.DataFrame {
  let n := df.nrows
  let col_vals := list.map(df.col_names, fn (nm :: Str) -> val.Value {
    val.vstr(nm)
  })
  let count_vals := list.map(df.col_names, fn (nm :: Str) -> val.Value {
    match map.get(df.columns, nm) {
      None => val.vnull(),
      Some(xs) => val.vint(list.len(list.filter(xs, fn (v :: val.Value) -> Bool {
        val.is_null(v)
      }))),
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

