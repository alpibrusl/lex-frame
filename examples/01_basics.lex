// Basic DataFrame operations with lex-frame
import "std.list" as list
import "std.str" as str
import "src/value" as val
import "src/frame" as frame
import "src/select" as sel
import "src/agg" as agg
import "src/inspect" as inspect

fn make_employees() -> Result[frame.DataFrame, frame.FrameError] {
  let names   = list.cons(val.VStr("Alice"),   list.cons(val.VStr("Bob"),   list.cons(val.VStr("Charlie"), list.cons(val.VStr("Dana"), []))))
  let depts   = list.cons(val.VStr("Eng"),     list.cons(val.VStr("Sales"), list.cons(val.VStr("Eng"),     list.cons(val.VStr("Sales"), []))))
  let salaries= list.cons(val.VInt(95000),    list.cons(val.VInt(72000),   list.cons(val.VInt(88000),    list.cons(val.VInt(67000), []))))
  let cols    = list.cons(("name", names), list.cons(("dept", depts), list.cons(("salary", salaries), [])))
  frame.from_columns(cols)
}

// 1. Display as Markdown table — ready for LLM context injection
fn show_table() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message)
    Ok(df) => inspect.to_markdown(df, 20)
  }
}

// 2. Filter rows with a predicate
fn engineers_only() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message)
    Ok(df) =>
      let pred = fn(row) -> Bool {
        match sel.row_get_or_null(row, "dept") {
          val.VStr(d) => d == "Eng"
          _ => false
        }
      }
      match sel.filter_rows(df, "dept == 'Eng'", pred) {
        Err(e)       => str.concat("Filter error: ", e.message)
        Ok(filtered) => inspect.to_markdown(filtered, 10)
      }
  }
}

// 3. Select a subset of columns
fn names_and_salaries() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message)
    Ok(df) =>
      let wanted = list.cons("name", list.cons("salary", []))
      match sel.select_cols(df, wanted) {
        Err(e)   => str.concat("Select error [code=", str.concat(e.code, str.concat("]: ", e.message)))
        Ok(slim) => inspect.to_markdown(slim, 10)
      }
  }
}

// 4. Aggregate a column
fn avg_salary() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message)
    Ok(df) =>
      match agg.mean_col(df, "salary") {
        None    => "no numeric data"
        Some(m) => str.concat("Mean salary: ", str.concat(float.to_str(m), " USD"))
      }
  }
}

// 5. Rich summary for AI agent consumption
fn agent_summary() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message)
    Ok(df) => inspect.summary(df)
  }
}
