import "std.str" as str

import "std.list" as list

import "std.map" as map

import "std.int" as int

import "std.float" as float

import "std.io" as io

import "./value" as val

import "./col" as col

import "./frame" as frame

import "./provenance" as prov

fn parse_csv(content :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  if str.is_empty(str.trim(content)) {
    Err(frame.frame_err("empty_input", "CSV content is empty", ""))
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
      None => Err(frame.frame_err("empty_input", "no header row found", "")),
      Some(hdr) => {
        let headers := list.map(str.split(hdr, ","), fn (s :: Str) -> Str {
          str.trim(s)
        })
        let data_rows := list.tail(lines)
        let n_cols := list.len(headers)
        let header_idx := list.fold(list.enumerate(headers), map.new(), fn (m :: Map[Str, Str], p :: (Int, Str)) -> Map[Str, Str] {
          let i := match p {
            (a, _) => a,
          }
          let name := match p {
            (_, b) => b,
          }
          map.set(m, int.to_str(i), name)
        })
        let init_acc := list.fold(headers, map.new(), fn (m :: Map[Str, List[val.Value]], name :: Str) -> Map[Str, List[val.Value]] {
          map.set(m, name, [])
        })
        let reversed_cols := list.fold(data_rows, init_acc, fn (col_acc :: Map[Str, List[val.Value]], line :: Str) -> Map[Str, List[val.Value]] {
          let raw_vals := str.split(line, ",")
          let padded := pad_or_trim(raw_vals, n_cols)
          let parsed := list.map(padded, fn (s :: Str) -> val.Value {
            val.parse_str(s)
          })
          list.fold(list.enumerate(parsed), col_acc, fn (m :: Map[Str, List[val.Value]], p :: (Int, val.Value)) -> Map[Str, List[val.Value]] {
            let idx := match p {
              (a, _) => a,
            }
            let v := match p {
              (_, b) => b,
            }
            match map.get(header_idx, int.to_str(idx)) {
              None => m,
              Some(name) => {
                let existing := match map.get(m, name) {
                  Some(xs) => xs,
                  None => [],
                }
                map.set(m, name, list.cons(v, existing))
              },
            }
          })
        })
        let cols := list.map(headers, fn (name :: Str) -> (Str, List[val.Value]) {
          let vals := match map.get(reversed_cols, name) {
            Some(xs) => list.reverse(xs),
            None => [],
          }
          (name, vals)
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

fn read_csv(path :: Str) -> [io] Result[frame.DataFrame, frame.FrameError] {
  match io.read(path) {
    Err(e) => Err(frame.frame_err("io_error", str.concat("read failed: ", e), path)),
    Ok(content) => parse_csv(content),
  }
}

fn write_csv(path :: Str, df :: frame.DataFrame) -> [io] Result[Unit, frame.FrameError] {
  match io.write(path, render_csv(df)) {
    Err(e) => Err(frame.frame_err("io_error", str.concat("write failed: ", e), path)),
    Ok(_) => Ok(()),
  }
}

