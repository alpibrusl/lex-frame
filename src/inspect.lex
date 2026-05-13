# lex-frame — AI-agent inspection helpers
#
# This is the “secret sauce” that makes lex-frame AI-agent-first.
# Traditional dataframe libraries (pandas, polars, spark) are built
# for humans in notebooks. Their display functions produce ANSI art
# and terminal-width-dependent wrapping — garbage for LLMs.
#
# Every function here produces output that is:
#   • Machine-readable (structured JSON or Markdown)
#   • Context-window budget-aware (max_rows cap)
#   • Self-documenting (column types, null counts, provenance)
#   • Action-oriented (includes error codes agents can act on)
#
# Design contrast with existing libraries:
#   pandas .describe()   → prints to stdout, ANSI-formatted, can’t budget
#   polars .glimpse()    → terminal display, no provenance
#   spark  .printSchema()→ side-effectful, no structured output
#   lex-frame summary()  → returns Str, JSON-embeddable, budgeted,
#                           provenance-included, machine-readable codes

import "std.list"  as list
import "std.map"   as map
import "std.str"   as str
import "std.int"   as int
import "std.float" as float
import "./value"      as val
import "./frame"      as frame
import "./agg"        as agg
import "./provenance" as prov
import "./stats"      as stats

# ---- Infer column types ------------------------------------------

# Returns a Map from column name to dominant type name.
# Dominant type: the most common non-null type in the column.
fn infer_dtypes(df :: frame.DataFrame) -> List[(Str, Str)] {
  list.map(df.col_names, fn (name :: Str) -> (Str, Str) {
    let dtype := match map.get(df.columns, name) {
      None     => "unknown",
      Some(xs) => dominant_type(xs),
    }
    (name, dtype)
  })
}

fn dominant_type(col :: List[Value]) -> Str {
  let non_null := list.filter(col, fn (v :: Value) -> Bool { not val.is_null(v) })
  if list.is_empty(non_null) { "null" }
  else {
    # Count each type.
    let counts := list.fold(non_null, map.new(),
      fn (m :: Map[Str, Int], v :: Value) -> Map[Str, Int] {
        let t := val.type_name(v)
        let c := match map.get(m, t) { Some(n) => n, None => 0 }
        map.set(m, t, c + 1)
      })
    # Find the type with the highest count.
    map.fold(counts, "unknown",
      fn (best :: Str, t :: Str, c :: Int) -> Str {
        match map.get(counts, best) {
          None    => t,
          Some(bc) => if c > bc { t } else { best },
        }
      })
  }
}

# ---- summary() ---------------------------------------------------
# Single-call overview. Designed for pasting into an LLM context.
fn summary(df :: frame.DataFrame) -> Str {
  let dtypes  := infer_dtypes(df)
  let nc_df   := stats.null_counts(df)
  let shape_s := str.concat(int.to_str(frame.n_rows(df)),
                   str.concat(" rows x ", str.concat(int.to_str(frame.n_cols(df)), " cols")))
  let cols_s  := str.join(list.map(dtypes, fn (p :: (Str, Str)) -> Str {
    let name  := match p { (a, _) => a }
    let dtype := match p { (_, b) => b }
    let nulls := match map.get(df.columns, name) {
      None     => 0,
      Some(xs) => list.len(list.filter(xs, fn (v :: Value) -> Bool { val.is_null(v) }))
    }
    str.concat("  ", str.concat(name, str.concat(" (", str.concat(dtype,
      str.concat(") null=", int.to_str(nulls))))))
  }), "\n")
  let hist_s  := prov.render_history(df.provenance)
  str.join([
    str.concat("Shape: ", shape_s),
    "Columns:",
    cols_s,
    "Provenance:",
    hist_s,
  ], "\n")
}

# ---- to_markdown() -----------------------------------------------
# GitHub-Markdown table. max_rows caps output for context windows.
fn to_markdown(df :: frame.DataFrame, max_rows :: Int) -> Str {
  let n    := int.min(max_rows, frame.n_rows(df))
  let cols := df.col_names
  let hdr  := str.concat("| ", str.concat(str.join(cols, " | "), " |"))
  let sep  := str.concat("| ", str.concat(str.join(list.map(cols, fn (_n :: Str) -> Str { "---" }), " | "), " |"))
  let rows := list.map(frame.range_list(0, n), fn (i :: Int) -> Str {
    let vals := list.map(cols, fn (name :: Str) -> Str {
      match map.get(df.columns, name) {
        None      => "null",
        Some(col) => val.to_str(frame.nth_value(col, i)),
      }
    })
    str.concat("| ", str.concat(str.join(vals, " | "), " |"))
  })
  str.join(list.concat([hdr, sep], rows), "\n")
}

# ---- to_json_payload() -------------------------------------------
# Compact JSON for LLM context windows. Includes schema + sampled rows.
# max_rows caps how many data rows are included (default: use 10).
fn to_json_payload(df :: frame.DataFrame, max_rows :: Int) -> Str {
  let n     := int.min(max_rows, frame.n_rows(df))
  let dtypes := infer_dtypes(df)
  let schema_entries := list.map(dtypes, fn (p :: (Str, Str)) -> Str {
    let name  := match p { (a, _) => a }
    let dtype := match p { (_, b) => b }
    str.concat("\"", str.concat(name, str.concat("\": \"", str.concat(dtype, "\"")))
  })
  let schema_s := str.concat("{\"columns\": {", str.concat(str.join(schema_entries, ", "), str.concat("}, \"shape\": [",
    str.concat(int.to_str(frame.n_rows(df)), str.concat(", ", str.concat(int.to_str(frame.n_cols(df)), "]")
  ))))
  let rows_s := list.map(frame.range_list(0, n), fn (i :: Int) -> Str {
    let pairs := list.map(df.col_names, fn (name :: Str) -> Str {
      let v := match map.get(df.columns, name) {
        None      => val.VNull,
        Some(col) => frame.nth_value(col, i),
      }
      str.concat("\"", str.concat(name, str.concat("\": ", json_val(v))))
    })
    str.concat("{", str.concat(str.join(pairs, ", "), "}"))
  })
  str.concat(schema_s, str.concat(", \"rows\": [", str.concat(str.join(rows_s, ", "), "]}")))
}

fn json_val(v :: Value) -> Str {
  match v {
    val.VNull     => "null",
    val.VBool(b)  => if b { "true" } else { "false" },
    val.VInt(n)   => int.to_str(n),
    val.VFloat(x) => float.to_str(x),
    val.VStr(s)   => str.concat("\"", str.concat(s, "\"")),
  }
}

# ---- column_profile() --------------------------------------------
# Per-column statistics as a human-readable string.
fn column_profile(df :: frame.DataFrame, col :: Str) -> Result[Str, frame.FrameError] {
  match map.get(df.columns, col) {
    None     => Err(frame.not_found_error(col)),
    Some(xs) => {
      let dtype     := dominant_type(xs)
      let n         := list.len(xs)
      let null_cnt  := list.len(list.filter(xs, fn (v :: Value) -> Bool { val.is_null(v) }))
      let non_null  := n - null_cnt
      let distinct  := agg.n_distinct(xs)
      let base := str.join([
        str.concat("column:   ", col),
        str.concat("dtype:    ", dtype),
        str.concat("count:    ", int.to_str(n)),
        str.concat("non-null: ", int.to_str(non_null)),
        str.concat("null:     ", int.to_str(null_cnt)),
        str.concat("distinct: ", int.to_str(distinct)),
      ], "\n")
      let numeric_s := if dtype == "int" or dtype == "float" {
        let mean_s := match agg.mean_col(xs) { Some(x) => float.to_str(x), None => "n/a" }
        let std_s  := match agg.std_col(xs)  { Some(x) => float.to_str(x), None => "n/a" }
        let min_s  := match agg.min_col(xs)  { Some(v) => val.to_str(v),   None => "n/a" }
        let max_s  := match agg.max_col(xs)  { Some(v) => val.to_str(v),   None => "n/a" }
        str.join([
          str.concat("mean:     ", mean_s),
          str.concat("std:      ", std_s),
          str.concat("min:      ", min_s),
          str.concat("max:      ", max_s),
        ], "\n")
      } else { "" }
      Ok(if str.is_empty(numeric_s) { base } else { str.concat(base, str.concat("\n", numeric_s)) })
    },
  }
}

# ---- history() ---------------------------------------------------
# Numbered provenance steps.
fn history(df :: frame.DataFrame) -> Str {
  prov.render_history(df.provenance)
}

# ---- sample_rows() -----------------------------------------------
# Returns n evenly-spaced rows (deterministic — no random effect).
# Safe for agents to call on very large frames.
fn sample_rows(df :: frame.DataFrame, n :: Int) -> frame.DataFrame {
  let actual := int.min(n, frame.n_rows(df))
  if actual <= 0 { frame.empty() }
  else if actual >= frame.n_rows(df) { df }
  else {
    let step    := frame.n_rows(df) / actual
    let indices := list.map(frame.range_list(0, actual), fn (i :: Int) -> Int { i * step })
    frame.pick_rows(df, indices)
  }
}

# ---- null_report() -----------------------------------------------
# Returns a 3-column DataFrame: column | null_count | null_pct
fn null_report(df :: frame.DataFrame) -> frame.DataFrame {
  let n := frame.n_rows(df)
  let col_vals   := list.map(df.col_names, fn (nm :: Str) -> Value { val.VStr(nm) })
  let count_vals := list.map(df.col_names, fn (nm :: Str) -> Value {
    match map.get(df.columns, nm) {
      None     => val.VNull,
      Some(xs) => val.VInt(list.len(list.filter(xs, fn (v :: Value) -> Bool { val.is_null(v) }))),
    }
  })
  let pct_vals := list.map(count_vals, fn (v :: Value) -> Value {
    match val.as_int(v) {
      None    => val.VNull,
      Some(c) => if n == 0 { val.VFloat(0.0) } else {
        val.VFloat(int.to_float(c) / int.to_float(n) * 100.0)
      },
    }
  })
  match frame.from_columns([("column", col_vals), ("null_count", count_vals), ("null_pct", pct_vals)]) {
    Ok(d)  => d,
    Err(_) => frame.empty(),
  }
}
