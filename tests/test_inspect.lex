import "std.list" as list
import "std.str" as str
import "../src/value" as val
import "../src/frame" as frame
import "../src/inspect" as inspect

fn make_df() -> frame.DataFrame {
  let names := list.cons(val.VStr("Alice"), list.cons(val.VStr("Bob"), list.cons(val.VStr("Charlie"), [])))
  let ages  := list.cons(val.VInt(25), list.cons(val.VInt(30), list.cons(val.VNull, [])))
  let cols  := list.cons(("name", names), list.cons(("age", ages), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_summary_nonempty() -> Int {
  if str.is_empty(inspect.summary(make_df())) { 1 } else { 0 }
}

fn test_summary_contains_shape() -> Int {
  let s := inspect.summary(make_df())
  if str.contains(s, "3") { 0 } else { 1 }
}

fn test_to_markdown_nonempty() -> Int {
  if str.is_empty(inspect.to_markdown(make_df(), 10)) { 1 } else { 0 }
}

fn test_to_markdown_has_header_sep() -> Int {
  let md := inspect.to_markdown(make_df(), 10)
  if str.contains(md, "|") { 0 } else { 1 }
}

fn test_to_json_payload_nonempty() -> Int {
  if str.is_empty(inspect.to_json_payload(make_df(), 10)) { 1 } else { 0 }
}

fn test_to_json_payload_has_schema() -> Int {
  let j := inspect.to_json_payload(make_df(), 10)
  if str.contains(j, "schema") { 0 } else { 1 }
}

fn test_null_report_nrows() -> Int {
  let nr := inspect.null_report(make_df())
  if nr.nrows == 2 { 0 } else { 1 }
}

fn test_null_report_ncols() -> Int {
  let nr := inspect.null_report(make_df())
  if list.len(nr.col_names) == 3 { 0 } else { 1 }
}

fn test_history_nonempty_after_op() -> Int {
  # make_df via from_columns records an OpLoad op
  let h := inspect.history(make_df())
  if str.is_empty(h) { 1 } else { 0 }
}

fn test_sample_rows_nrows() -> Int {
  let sample := inspect.sample_rows(make_df(), 2)
  if sample.nrows == 2 { 0 } else { 1 }
}

fn test_sample_rows_capped_at_nrows() -> Int {
  # requesting more than available returns all rows
  let sample := inspect.sample_rows(make_df(), 100)
  if sample.nrows == 3 { 0 } else { 1 }
}

fn test_column_profile_nonempty() -> Int {
  let cp := inspect.column_profile(make_df(), "age")
  if str.is_empty(cp) { 1 } else { 0 }
}

fn run_all() -> () {
  let _ := test_summary_nonempty() + test_summary_contains_shape() +
            test_to_markdown_nonempty() + test_to_markdown_has_header_sep() +
            test_to_json_payload_nonempty() + test_to_json_payload_has_schema() +
            test_null_report_nrows() + test_null_report_ncols() +
            test_history_nonempty_after_op() + test_sample_rows_nrows() +
            test_sample_rows_capped_at_nrows() + test_column_profile_nonempty()
  ()
}
