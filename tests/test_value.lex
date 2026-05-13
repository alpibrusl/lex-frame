import "std.list" as list

import "../src/value" as val

fn test_vint_to_str() -> Int {
  if val.to_str(val.vint(42)) == "42" {
    0
  } else {
    1
  }
}

fn test_vfloat_to_str() -> Int {
  if val.to_str(val.vfloat(1.5)) == "1.5" {
    0
  } else {
    1
  }
}

fn test_vbool_to_str() -> Int {
  if val.to_str(val.vbool(true)) == "true" {
    0
  } else {
    1
  }
}

fn test_vstr_to_str() -> Int {
  if val.to_str(val.vstr("hello")) == "hello" {
    0
  } else {
    1
  }
}

fn test_vnull_to_str() -> Int {
  if val.to_str(val.vnull()) == "null" {
    0
  } else {
    1
  }
}

fn test_type_name_int() -> Int {
  if val.type_name(val.vint(1)) == "Int" {
    0
  } else {
    1
  }
}

fn test_type_name_float() -> Int {
  if val.type_name(val.vfloat(1.0)) == "Float" {
    0
  } else {
    1
  }
}

fn test_type_name_str() -> Int {
  if val.type_name(val.vstr("x")) == "Str" {
    0
  } else {
    1
  }
}

fn test_type_name_bool() -> Int {
  if val.type_name(val.vbool(false)) == "Bool" {
    0
  } else {
    1
  }
}

fn test_type_name_null() -> Int {
  if val.type_name(val.vnull()) == "Null" {
    0
  } else {
    1
  }
}

fn test_is_null_true() -> Int {
  if val.is_null(val.vnull()) {
    0
  } else {
    1
  }
}

fn test_is_null_false() -> Int {
  if val.is_null(val.vint(0)) {
    1
  } else {
    0
  }
}

fn test_is_numeric_int() -> Int {
  if val.is_numeric(val.vint(5)) {
    0
  } else {
    1
  }
}

fn test_is_numeric_float() -> Int {
  if val.is_numeric(val.vfloat(2.0)) {
    0
  } else {
    1
  }
}

fn test_is_numeric_str() -> Int {
  if val.is_numeric(val.vstr("5")) {
    1
  } else {
    0
  }
}

fn test_eq_int_same() -> Int {
  if val.eq(val.vint(3), val.vint(3)) {
    0
  } else {
    1
  }
}

fn test_eq_int_diff() -> Int {
  if val.eq(val.vint(1), val.vint(2)) {
    1
  } else {
    0
  }
}

fn test_eq_int_float_widening() -> Int {
  if val.eq(val.vint(3), val.vfloat(3.0)) {
    0
  } else {
    1
  }
}

fn test_lt_int() -> Int {
  if val.lt(val.vint(1), val.vint(2)) {
    0
  } else {
    1
  }
}

fn test_lt_null_is_lowest() -> Int {
  if val.lt(val.vnull(), val.vint(0)) {
    0
  } else {
    1
  }
}

fn test_parse_str_int() -> Int {
  let v := val.parse_str("42")
  match val.as_int(v) {
    Some(n) => if n == 42 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_parse_str_float() -> Int {
  let v := val.parse_str("3.14")
  match val.as_float(v) {
    Some(_) => 0,
    None => 1,
  }
}

fn test_parse_str_bool_true() -> Int {
  let v := val.parse_str("true")
  match val.as_bool(v) {
    Some(b) => if b {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_parse_str_bool_false() -> Int {
  let v := val.parse_str("false")
  match val.as_bool(v) {
    Some(b) => if b {
      1
    } else {
      0
    },
    None => 1,
  }
}

fn test_parse_str_null() -> Int {
  if val.is_null(val.parse_str("null")) {
    0
  } else {
    1
  }
}

fn test_parse_str_fallback() -> Int {
  let v := val.parse_str("hello world")
  match val.as_str(v) {
    Some(s) => if s == "hello world" {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_as_float_int() -> Int {
  match val.as_float(val.vint(3)) {
    Some(f) => if f == 3.0 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_as_float_float() -> Int {
  match val.as_float(val.vfloat(2.5)) {
    Some(f) => if f == 2.5 {
      0
    } else {
      1
    },
    None => 1,
  }
}

fn test_as_float_null() -> Int {
  match val.as_float(val.vnull()) {
    Some(_) => 1,
    None => 0,
  }
}

fn test_as_float_str() -> Int {
  match val.as_float(val.vstr("hello")) {
    Some(_) => 1,
    None => 0,
  }
}

fn run_all() -> Unit {
  let __lex_discard_1 := test_vint_to_str() + test_vfloat_to_str() + test_vbool_to_str() + test_vstr_to_str() + test_vnull_to_str() + test_type_name_int() + test_type_name_float() + test_type_name_str() + test_type_name_bool() + test_type_name_null() + test_is_null_true() + test_is_null_false() + test_is_numeric_int() + test_is_numeric_float() + test_is_numeric_str() + test_eq_int_same() + test_eq_int_diff() + test_eq_int_float_widening() + test_lt_int() + test_lt_null_is_lowest() + test_parse_str_int() + test_parse_str_float() + test_parse_str_bool_true() + test_parse_str_bool_false() + test_parse_str_null() + test_parse_str_fallback() + test_as_float_int() + test_as_float_float() + test_as_float_null() + test_as_float_str()
  ()
}

