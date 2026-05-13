# lex-frame — CSV and JSON row I/O
#
# Pure functions: parse_csv, render_csv, parse_json_rows, render_json_rows
# Effect-bearing: read_csv [fs.read], write_csv [fs.write]
#
# CSV uses comma delimiter and a header row.
# JSON rows format: [{"col":val,...}, ...] (array of objects).

import "std.str"   as str
import "std.list"  as list
import "std.int"   as int
import "std.float" as float
import "std.json"  as json
import "std.io"    as io
import "./value"      as val
import "./frame"      as frame
import "./provenance" as prov

# ---- CSV — pure -------------------------------------------------

# Parse a CSV string into a DataFrame.
# First row is headers. Values are heuristically typed via val.parse_str.
# Note: quoted fields containing commas are not supported in v0.1.
fn parse_csv(content :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  let raw_lines := str.split(str.trim(content), "\n")
  let lines     := list.filter(raw_lines, fn (l :: Str) -> Bool { not str.is_empty(str.trim(l)) })
  match list.head(lines) {
    None      => Ok(frame.empty()),
    Some(hdr) => {
      let headers   := list.map(str.split(hdr, ","), fn (s :: Str) -> Str { str.trim(s) })
      let data_rows := list.tail(lines)
      let n_cols    := list.len(headers)
      let parsed_rows := list.map(data_rows, fn (line :: Str) -> List[Value] {
        let raw_vals := str.split(line, ",")
        # Pad or trim to n_cols for robustness.
        let padded := pad_or_trim(raw_vals, n_cols)
        list.map(padded, fn (s :: Str) -> Value { val.parse_str(s) })
      })
      let cols := list.map(list.enumerate(headers), fn (p :: (Int, Str)) -> (Str, List[Value]) {
        let col_idx  := match p { (a, _) => a }
        let col_name := match p { (_, b) => b }
        let col_vals := list.map(parsed_rows, fn (row :: List[Value]) -> Value {
          frame.nth_value(row, col_idx)
        })
        (col_name, col_vals)
      })
      match frame.from_columns(cols) {
        Err(e)  => Err(e),
        Ok(df)  => Ok(frame.record_op(df, prov.op_load("csv", df.nrows))),
      }
    },
  }
}

# Render a DataFrame to CSV string (header + data rows).
fn render_csv(df :: frame.DataFrame) -> Str {
  let header := str.join(df.col_names, ",")
  let rows   := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> Str {
    let vals := list.map(df.col_names, fn (name :: Str) -> Str {
      let v := match map.get(df.columns, name) {
        None      => "null",
        Some(col) => csv_escape(val.to_str(frame.nth_value(col, i))),
      }
      v
    })
    str.join(vals, ",")
  })
  str.join(list.concat([header], rows), "\n")
}

# Wrap values containing commas or quotes in double-quotes.
fn csv_escape(s :: Str) -> Str {
  if str.contains(s, ",") or str.contains(s, "\"") {
    str.concat("\"", str.concat(str.replace(s, "\"", "\"\""), "\""))
  } else { s }
}

# Pad list to n elements with empty string; trim if longer.
fn pad_or_trim(xs :: List[Str], n :: Int) -> List[Str] {
  let current := list.len(xs)
  if current == n { xs }
  else if current < n {
    list.concat(xs, list.map(frame.range_list(0, n - current), fn (_i :: Int) -> Str { "" }))
  } else {
    list.reverse(list.fold(list.enumerate(xs), [],
      fn (acc :: List[Str], p :: (Int, Str)) -> List[Str] {
        let i := match p { (a, _) => a }
        let s := match p { (_, b) => b }
        if i < n { list.cons(s, acc) } else { acc }
      }))
  }
}

import "std.map" as map

# ---- JSON rows — render (pure) -----------------------------------

# Render a DataFrame as a JSON array of row objects.
fn render_json_rows(df :: frame.DataFrame) -> Str {
  let rows := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> Str {
    let pairs := list.map(df.col_names, fn (name :: Str) -> Str {
      let v := match map.get(df.columns, name) {
        None      => val.VNull,
        Some(col) => frame.nth_value(col, i),
      }
      str.concat("\"", str.concat(name, str.concat("\": ", json_value(v))))
    })
    str.concat("{", str.concat(str.join(pairs, ", "), "}"))
  })
  str.concat("[", str.concat(str.join(rows, ",\n"), "]"))
}

fn json_value(v :: Value) -> Str {
  match v {
    val.VNull     => "null",
    val.VBool(b)  => if b { "true" } else { "false" },
    val.VInt(n)   => int.to_str(n),
    val.VFloat(x) => float.to_str(x),
    val.VStr(s)   => str.concat("\"", str.concat(json_escape(s), "\"")),
  }
}

fn json_escape(s :: Str) -> Str {
  let chars := str.split(s, "")
  list.fold(chars, "", fn (acc :: Str, c :: Str) -> Str {
    str.concat(acc, match c {
      "\"" => "\\\"",
      "\\" => "\\\\",
      "\n" => "\\n",
      "\r" => "\\r",
      "\t" => "\\t",
      _    => c,
    })
  })
}

# ---- File I/O — effect-bearing -----------------------------------

fn read_csv(path :: Str) -> [fs.read] Result[frame.DataFrame, frame.FrameError] {
  match io.read(path) {
    Err(e)      => Err(frame.frame_error("io_error", str.concat("read failed: ", e), path)),
    Ok(content) => parse_csv(content),
  }
}

fn write_csv(path :: Str, df :: frame.DataFrame) -> [fs.write] Result[Unit, frame.FrameError] {
  match io.write(path, render_csv(df)) {
    Err(e) => Err(frame.frame_error("io_error", str.concat("write failed: ", e), path)),
    Ok(()) => Ok(()),
  }
}
