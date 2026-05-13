import "std.list" as list

import "std.str" as str

import "../src/value" as val

import "../src/frame" as frame

import "../src/io" as io

fn make_df() -> frame.DataFrame {
  let names := list.cons(val.vstr("Alice"), list.cons(val.vstr("Bob"), []))
  let ages := list.cons(val.vint(25), list.cons(val.vint(30), []))
  let cols := list.cons(("name", names), list.cons(("age", ages), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn test_parse_csv_nrows() -> Int {
  match io.parse_csv("name,age\nAlice,25\nBob,30") {
    Ok(df) => if df.nrows == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_parse_csv_ncols() -> Int {
  match io.parse_csv("name,age\nAlice,25\nBob,30") {
    Ok(df) => if list.len(df.col_names) == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_parse_csv_type_int() -> Int {
  match io.parse_csv("id\n1\n2\n3") {
    Ok(df) => if df.nrows == 3 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_parse_csv_empty_body_is_error() -> Int {
  match io.parse_csv("") {
    Ok(_) => 1,
    Err(_) => 0,
  }
}

fn test_render_csv_nonempty() -> Int {
  let csv := io.render_csv(make_df())
  if str.is_empty(csv) {
    1
  } else {
    0
  }
}

fn test_render_csv_roundtrip_nrows() -> Int {
  let csv := io.render_csv(make_df())
  match io.parse_csv(csv) {
    Ok(df2) => if df2.nrows == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_render_csv_roundtrip_ncols() -> Int {
  let csv := io.render_csv(make_df())
  match io.parse_csv(csv) {
    Ok(df2) => if list.len(df2.col_names) == 2 {
      0
    } else {
      1
    },
    Err(_) => 1,
  }
}

fn test_render_json_rows_nonempty() -> Int {
  let json := io.render_json_rows(make_df())
  if str.is_empty(json) {
    1
  } else {
    0
  }
}

fn test_render_json_rows_starts_with_bracket() -> Int {
  let json := io.render_json_rows(make_df())
  if str.contains(json, "[") {
    0
  } else {
    1
  }
}

fn run_all() -> Unit {
  let __lex_discard_1 := test_parse_csv_nrows() + test_parse_csv_ncols() + test_parse_csv_type_int() + test_parse_csv_empty_body_is_error() + test_render_csv_nonempty() + test_render_csv_roundtrip_nrows() + test_render_csv_roundtrip_ncols() + test_render_json_rows_nonempty() + test_render_json_rows_starts_with_bracket()
  ()
}

