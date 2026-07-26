# Basic DataFrame operations with lex-frame

import "std.list" as list

import "std.str" as str

import "std.float" as float

import "../src/value" as val

import "../src/frame" as frame

import "../src/select" as sel

import "../src/agg" as agg

import "../src/inspect" as inspect

fn make_employees() -> Result[frame.DataFrame, frame.FrameError] {
  let names := list.cons(val.vstr("Alice"), list.cons(val.vstr("Bob"), list.cons(val.vstr("Charlie"), list.cons(val.vstr("Dana"), []))))
  let depts := list.cons(val.vstr("Eng"), list.cons(val.vstr("Sales"), list.cons(val.vstr("Eng"), list.cons(val.vstr("Sales"), []))))
  let salaries := list.cons(val.vint(95000), list.cons(val.vint(72000), list.cons(val.vint(88000), list.cons(val.vint(67000), []))))
  let cols := list.cons(("name", names), list.cons(("dept", depts), list.cons(("salary", salaries), [])))
  frame.from_columns(cols)
}

# 1. Display as Markdown table — ready for LLM context injection
fn show_table() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message),
    Ok(df) => inspect.to_markdown(df, 20),
  }
}

# 2. Filter rows with a predicate
fn engineers_only() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message),
    Ok(df) => {
      let pred := fn (row :: List[(Str, val.Value)]) -> Bool {
        match val.as_str(sel.row_get_or_null(row, "dept")) {
          Some(d) => d == "Eng",
          None => false,
        }
      }
      match sel.filter_rows(df, "dept == 'Eng'", pred) {
        Err(e) => str.concat("Filter error: ", e.message),
        Ok(filtered) => inspect.to_markdown(filtered, 10),
      }
    },
  }
}

# 3. Select a subset of columns
fn names_and_salaries() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message),
    Ok(df) => {
      let wanted := list.cons("name", list.cons("salary", []))
      match sel.select_cols(df, wanted) {
        Err(e) => str.concat("Select error [code=", str.concat(e.code, str.concat("]: ", e.message))),
        Ok(slim) => inspect.to_markdown(slim, 10),
      }
    },
  }
}

# 4. Aggregate a column
fn avg_salary() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message),
    Ok(df) => match agg.mean_col(df, "salary") {
      None => "no numeric data",
      Some(m) => str.concat("Mean salary: ", str.concat(float.to_str(m), " USD")),
    },
  }
}

# 5. Rich summary for AI agent consumption
fn agent_summary() -> Str {
  match make_employees() {
    Err(e) => str.concat("Error: ", e.message),
    Ok(df) => inspect.summary(df),
  }
}

fn main() -> Str {
  str.concat(show_table(), str.concat("\n\n", str.concat(engineers_only(), str.concat("\n\n", str.concat(names_and_salaries(), str.concat("\n\n", str.concat(avg_salary(), str.concat("\n\n", agent_summary()))))))))
}

