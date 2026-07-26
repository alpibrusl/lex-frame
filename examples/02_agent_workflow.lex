# AI-agent-first workflow: structured errors, JSON payloads, provenance

import "std.list" as list

import "std.str" as str

import "../src/value" as val

import "../src/frame" as frame

import "../src/select" as sel

import "../src/sort" as srt

import "../src/inspect" as inspect

# Agents receive machine-readable error codes, never free-form panics.
# Error codes follow the pattern MODULE_REASON so agents can branch on them.
fn demonstrate_structured_errors() -> Str {
  let bad_cols := list.cons(("a", list.cons(val.vint(1), list.cons(val.vint(2), []))), list.cons(("b", list.cons(val.vint(9), [])), []))
  match frame.from_columns(bad_cols) {
    Ok(_) => "unexpected success",
    Err(e) => str.concat("[code=", str.concat(e.code, str.concat("] ", e.message))),
  }
}

# Agents get compact JSON snapshots that fit within context windows.
fn demonstrate_json_payload() -> Str {
  let names := list.cons(val.vstr("Alice"), list.cons(val.vstr("Bob"), list.cons(val.vstr("Charlie"), [])))
  let ages := list.cons(val.vint(28), list.cons(val.vint(34), list.cons(val.vint(22), [])))
  let cols := list.cons(("name", names), list.cons(("age", ages), []))
  match frame.from_columns(cols) {
    Err(e) => str.concat("Error: ", e.message),
    Ok(df) => inspect.to_json_payload(df, 3),
  }
}

# Agents audit what happened to a DataFrame via its provenance log.
fn demonstrate_provenance() -> Str {
  let nums := list.cons(val.vint(3), list.cons(val.vint(1), list.cons(val.vint(2), [])))
  let cols := list.cons(("n", nums), [])
  match frame.from_columns(cols) {
    Err(e) => str.concat("Error: ", e.message),
    Ok(df) => {
      let sorted := srt.sort_by(df, "n", true)
      let pred := fn (row :: List[(Str, val.Value)]) -> Bool {
        match val.as_int(sel.row_get_or_null(row, "n")) {
          Some(n) => n > 1,
          None => false,
        }
      }
      match sel.filter_rows(sorted, "n > 1", pred) {
        Err(e) => str.concat("Error: ", e.message),
        Ok(kept) => inspect.history(kept),
      }
    },
  }
}

# Named pipe combinator: agents compose pipelines with readable step labels.
fn demonstrate_pipe() -> Str {
  let nums := list.cons(val.vint(5), list.cons(val.vint(3), list.cons(val.vint(8), list.cons(val.vint(1), []))))
  let cols := list.cons(("score", nums), [])
  match frame.from_columns(cols) {
    Err(e) => str.concat("Error: ", e.message),
    Ok(df) => {
      let step1 := frame.pipe(df, "sort_desc", fn (d :: frame.DataFrame) -> frame.DataFrame {
        srt.sort_by(d, "score", false)
      })
      let step2 := frame.pipe(step1, "top_3", fn (d :: frame.DataFrame) -> frame.DataFrame {
        frame.head(d, 3)
      })
      inspect.history(step2)
    },
  }
}

fn main() -> Str {
  str.concat(demonstrate_structured_errors(), str.concat("\n\n", str.concat(demonstrate_json_payload(), str.concat("\n\n", str.concat(demonstrate_provenance(), str.concat("\n\n", demonstrate_pipe()))))))
}

