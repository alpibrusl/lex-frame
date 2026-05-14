// AI-agent-first workflow: structured errors, JSON payloads, provenance
import "std.list" as list
import "std.str" as str
import "src/value" as val
import "src/frame" as frame
import "src/select" as sel
import "src/agg" as agg
import "src/sort" as srt
import "src/inspect" as inspect

// Agents receive machine-readable error codes, never free-form panics.
// Error codes follow the pattern MODULE_REASON so agents can branch on them.
fn demonstrate_structured_errors() -> Str {
  let bad_cols = list.cons(
    ("a", list.cons(val.VInt(1), list.cons(val.VInt(2), []))),
    list.cons(
      ("b", list.cons(val.VInt(9), [])),   // length mismatch
      []
    )
  )
  match frame.from_columns(bad_cols) {
    Ok(_)  => "unexpected success"
    Err(e) =>
      // e.code is machine-readable (e.g. "FRAME_LENGTH_MISMATCH")
      // e.message is human-readable for logs
      // Agents branch on e.code, not on string-matching e.message
      str.concat("[code=", str.concat(e.code, str.concat("] ", e.message)))
  }
}

// Agents get compact JSON snapshots that fit within context windows.
fn demonstrate_json_payload() -> Str {
  let names = list.cons(val.VStr("Alice"), list.cons(val.VStr("Bob"), list.cons(val.VStr("Charlie"), [])))
  let ages  = list.cons(val.VInt(28), list.cons(val.VInt(34), list.cons(val.VInt(22), [])))
  let cols  = list.cons(("name", names), list.cons(("age", ages), []))
  match frame.from_columns(cols) {
    Err(e) => str.concat("Error: ", e.message)
    Ok(df) =>
      // max_rows limits how much goes into context; schema is always included
      inspect.to_json_payload(df, 3)
  }
}

// Agents audit what happened to a DataFrame via its provenance log.
fn demonstrate_provenance() -> Str {
  let nums = list.cons(val.VInt(3), list.cons(val.VInt(1), list.cons(val.VInt(2), [])))
  let cols = list.cons(("n", nums), [])
  match frame.from_columns(cols) {
    Err(e) => str.concat("Error: ", e.message)
    Ok(df) =>
      // Every transform appends an Op to df.provenance immutably
      let sorted   = srt.sort_by(df, "n", true)
      let pred     = fn(row) -> Bool {
        match sel.row_get_or_null(row, "n") {
          val.VInt(n) => n > 1
          _ => false
        }
      }
      match sel.filter_rows(sorted, "n > 1", pred) {
        Err(e)    => str.concat("Error: ", e.message)
        Ok(final) => inspect.history(final)  // numbered audit trail
      }
  }
}

// Named pipe combinator: agents compose pipelines with readable step labels.
fn demonstrate_pipe() -> Str {
  let nums = list.cons(val.VInt(5), list.cons(val.VInt(3), list.cons(val.VInt(8), list.cons(val.VInt(1), []))))
  let cols = list.cons(("score", nums), [])
  match frame.from_columns(cols) {
    Err(e) => str.concat("Error: ", e.message)
    Ok(df) =>
      // pipe wraps a transform and records its name in provenance
      let step1 = frame.pipe(df, "sort_desc", fn(d) -> frame.DataFrame {
        srt.sort_by(d, "score", false)
      })
      let step2 = frame.pipe(step1, "top_3", fn(d) -> frame.DataFrame {
        frame.head(d, 3)
      })
      inspect.history(step2)
  }
}
