import "std.str" as str

import "std.list" as list

import "std.map" as map

import "std.int" as int

import "std.float" as float

import "std.io" as io

import "std.arrow" as arrow

import "./value" as val

import "./col" as col

import "./frame" as frame

import "./provenance" as prov

fn parse_csv(content :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  if str.is_empty(str.trim(content)) {
    Err(frame.frame_err("IO_EMPTY_INPUT", "CSV content is empty", ""))
  } else {
    let raw_lines := str.split(str.trim(content), "\n")
    let lines := list.filter(raw_lines, fn (l :: Str) -> Bool {
      if str.is_empty(str.trim(l)) {
        false
      } else {
        true
      }
    })
    match list.head(lines) {
      None => Err(frame.frame_err("IO_EMPTY_INPUT", "no header row found", "")),
      Some(hdr) => {
        let headers := list.map(str.split(hdr, ","), fn (s :: Str) -> Str {
          str.trim(s)
        })
        let data_rows := list.tail(lines)
        let n_cols := list.len(headers)
        let parsed_rows := list.map(data_rows, fn (line :: Str) -> List[val.Value] {
          let raw_vals := str.split(line, ",")
          let padded := pad_or_trim(raw_vals, n_cols)
          list.map(padded, fn (s :: Str) -> val.Value {
            val.parse_str(s)
          })
        })
        let cols := list.map(list.enumerate(headers), fn (p :: (Int, Str)) -> (Str, List[val.Value]) {
          let col_idx := match p {
            (a, _) => a,
          }
          let col_name := match p {
            (_, b) => b,
          }
          let col_vals := list.map(parsed_rows, fn (row :: List[val.Value]) -> val.Value {
            nth_val_list(row, col_idx)
          })
          (col_name, col_vals)
        })
        match frame.from_columns(cols) {
          Err(e) => Err(e),
          Ok(df) => Ok(frame.record_op(df, prov.op_load("csv", df.nrows))),
        }
      },
    }
  }
}

fn render_csv(df :: frame.DataFrame) -> Str {
  let header := str.join(df.col_names, ",")
  let rows := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> Str {
    let vals := list.map(df.col_names, fn (name :: Str) -> Str {
      match map.get(df.columns, name) {
        None => "",
        Some(c) => csv_escape(val.to_str(frame.nth_value(c, i))),
      }
    })
    str.join(vals, ",")
  })
  str.join(list.cons(header, rows), "\n")
}

fn csv_escape(s :: Str) -> Str {
  if str.contains(s, ",") or str.contains(s, "\"") {
    str.concat("\"", str.concat(str.replace(s, "\"", "\"\""), "\""))
  } else {
    s
  }
}

fn pad_or_trim(xs :: List[Str], n :: Int) -> List[Str] {
  let current := list.len(xs)
  if current == n {
    xs
  } else {
    if current < n {
      let pads := list.map(frame.range_list(0, n - current), fn (_i :: Int) -> Str {
        ""
      })
      let combined_rev := list.fold(pads, list.reverse(xs), fn (a :: List[Str], s :: Str) -> List[Str] {
        list.cons(s, a)
      })
      list.reverse(combined_rev)
    } else {
      list.reverse(list.fold(list.enumerate(xs), [], fn (acc :: List[Str], p :: (Int, Str)) -> List[Str] {
        let i := match p {
          (a, _) => a,
        }
        let s := match p {
          (_, b) => b,
        }
        if i < n {
          list.cons(s, acc)
        } else {
          acc
        }
      }))
    }
  }
}

fn render_json_rows(df :: frame.DataFrame) -> Str {
  let rows := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> Str {
    let pairs := list.map(df.col_names, fn (name :: Str) -> Str {
      let v := match map.get(df.columns, name) {
        None => val.vnull(),
        Some(c) => frame.nth_value(c, i),
      }
      str.concat("\"", str.concat(name, str.concat("\": ", json_value(v))))
    })
    str.concat("{", str.concat(str.join(pairs, ", "), "}"))
  })
  str.concat("[", str.concat(str.join(rows, ",\n"), "]"))
}

fn json_value(v :: val.Value) -> Str {
  let t := val.type_name(v)
  if t == "Null" {
    "null"
  } else {
    if t == "Bool" or t == "Int" or t == "Float" {
      val.to_str(v)
    } else {
      str.concat("\"", str.concat(json_escape(val.to_str(v)), "\""))
    }
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
      _ => c,
    })
  })
}

fn nth_val_list(xs :: List[val.Value], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(), fn (acc :: Map[Str, val.Value], p :: (Int, val.Value)) -> Map[Str, val.Value] {
    let idx := match p {
      (a, _) => a,
    }
    let v := match p {
      (_, b) => b,
    }
    map.set(acc, int.to_str(idx), v)
  })
  match map.get(m, int.to_str(i)) {
    Some(v) => v,
    None => val.vnull(),
  }
}

fn read_csv(path :: Str) -> [io] Result[frame.DataFrame, frame.FrameError] {
  match io.read(path) {
    Err(e) => Err(frame.frame_err("IO_READ_FAILED", str.concat("read failed: ", e), path)),
    Ok(content) => parse_csv(content),
  }
}

# Fast-path CSV reader: goes through `arrow.read_csv` (one Rust call
# over a flat buffer, schema inferred from the first 100 rows) and
# returns a DataFrame whose `arrow_table` is set. agg.*_fast ops
# dispatch through arrow kernels. Effect is `[fs_read]` (matches
# `arrow.read_csv` / `io.read` scope: `--allow-fs-read`).
#
# At 1M rows this is ~3-4 orders of magnitude faster than the legacy
# `read_csv` (which runs the CSV parser in interpreted Lex bytecode);
# the win compounds with `agg.sum_col_fast` etc. on the result. See
# `bench/REPORT.md` for measured numbers.
fn read_csv_fast(path :: Str) -> [fs_read] Result[frame.DataFrame, frame.FrameError] {
  match arrow.read_csv(path) {
    Err(e) => Err(frame.frame_err("IO_READ_FAILED", str.concat("arrow.read_csv failed: ", e), path)),
    Ok(t) => Ok(frame.from_arrow_table(t)),
  }
}

# Legacy CSV writer renders from the legacy columns map — an
# arrow-backed frame refuses (pre-#19 it silently wrote a
# header-only file). Use write_csv_fast for arrow frames.
fn write_csv(path :: Str, df :: frame.DataFrame) -> [io] Result[Unit, frame.FrameError] {
  match df.arrow_table {
    Some(_) => Err(frame.legacy_only_error("write_csv", "use write_csv_fast (arrow.write_csv kernel, [fs_write] effect)")),
    None => match io.write(path, render_csv(df)) {
      Err(e) => Err(frame.frame_err("IO_WRITE_FAILED", str.concat("write failed: ", e), path)),
      Ok(_) => Ok(()),
    },
  }
}

# Fast-path CSV writer for arrow-backed DataFrames: one
# `arrow.write_csv` call over the columnar buffer, under the narrow
# `[fs_write]` effect. List-backed frames are rejected rather than
# silently falling back — the legacy `write_csv` fallback would
# require the wider `[io]` effect in this signature, defeating the
# per-path `--allow-fs-write` policy scoping. Use `write_csv` for
# list-backed frames.
fn write_csv_fast(path :: Str, df :: frame.DataFrame) -> [fs_write] Result[Unit, frame.FrameError] {
  match df.arrow_table {
    None => Err(frame.frame_err("IO_WRITE_FAILED", "write_csv_fast requires an arrow-backed DataFrame (built via io.read_csv_fast / io.read_parquet / frame.from_arrow_table); use write_csv for list-backed frames", path)),
    Some(t) => match arrow.write_csv(t, path) {
      Err(e) => Err(frame.frame_err("IO_WRITE_FAILED", str.concat("arrow.write_csv failed: ", e), path)),
      Ok(_) => Ok(()),
    },
  }
}

# Parquet I/O — arrow-backed only (there is no interpreted parquet
# codec, by design: parquet exists here for scale, and scale means
# the arrow path). `read_parquet` returns an arrow-backed DataFrame
# ready for the `_fast` op pipeline.
fn read_parquet(path :: Str) -> [fs_read] Result[frame.DataFrame, frame.FrameError] {
  match arrow.read_parquet(path) {
    Err(e) => Err(frame.frame_err("IO_READ_FAILED", str.concat("arrow.read_parquet failed: ", e), path)),
    Ok(t) => Ok(frame.from_arrow_table(t)),
  }
}

# Column-projected parquet read: only the named columns are decoded
# (the projection is pushed into the parquet reader). Prefer this
# over `read_parquet` + `select_cols` when you need a subset of a
# wide file.
fn read_parquet_cols(path :: Str, cols :: List[Str]) -> [fs_read] Result[frame.DataFrame, frame.FrameError] {
  match arrow.read_parquet_cols(path, cols) {
    Err(e) => Err(frame.frame_err("IO_READ_FAILED", str.concat("arrow.read_parquet_cols failed: ", e), path)),
    Ok(t) => Ok(frame.from_arrow_table(t)),
  }
}

fn write_parquet(path :: Str, df :: frame.DataFrame) -> [fs_write] Result[Unit, frame.FrameError] {
  match df.arrow_table {
    None => Err(frame.frame_err("IO_WRITE_FAILED", "write_parquet requires an arrow-backed DataFrame (built via io.read_csv_fast / io.read_parquet / frame.from_arrow_table)", path)),
    Some(t) => match arrow.write_parquet(t, path) {
      Err(e) => Err(frame.frame_err("IO_WRITE_FAILED", str.concat("arrow.write_parquet failed: ", e), path)),
      Ok(_) => Ok(()),
    },
  }
}

