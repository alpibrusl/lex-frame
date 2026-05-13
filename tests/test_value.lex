import "std.list" as list
import "../src/value" as val

fn test_vint_to_str() -> Int {
  if val.to_str(val.VInt(42)) == "42" { 0 } else { 1 }
}

fn test_vfloat_to_str() -> Int {
  if val.to_str(val.VFloat(1.5)) == "1.5" { 0 } else { 1 }
}

fn test_vbool_to_str() -> Int {
  if val.to_str(val.VBool(true)) == "true" { 0 } else { 1 }
}

fn test_vstr_to_str() -> Int {
  if val.to_str(val.VStr("hello")) == "hello" { 0 } else { 1 }
}

fn test_vnull_to_str() -> Int {
  if val.to_str(val.VNull) == "null" { 0 } else { 1 }
}

fn test_type_name_int() -> Int {
  if val.type_name(val.VInt(1)) == "Int" { 0 } else { 1 }
}

fn test_type_name_float() -> Int {
  if val.type_name(val.VFloat(1.0)) == "Float" { 0 } else { 1 }
}

fn test_type_name_str() -> Int {
  if val.type_name(val.VStr("x")) == "Str" { 0 } else { 1 }
}

fn test_type_name_bool() -> Int {
  if val.type_name(val.VBool(false)) == "Bool" { 0 } else { 1 }
}

fn test_type_name_null() -> Int {
  if val.type_name(val.VNull) == "Null" { 0 } else { 1 }
}

fn test_is_null_true() -> Int {
  if val.is_null(val.VNull) { 0 } else { 1 }
}

fn test_is_null_false() -> Int {
  if val.is_null(val.VInt(0)) { 1 } else { 0 }
}

fn test_is_numeric_int() -> Int {
  if val.is_numeric(val.VInt(5)) { 0 } else { 1 }
}

fn test_is_numeric_float() -> Int {
  if val.is_numeric(val.VFloat(2.0)) { 0 } else { 1 }
}

fn test_is_numeric_str() -> Int {
  if val.is_numeric(val.VStr("5")) { 1 } else { 0 }
}

fn test_eq_int_same() -> Int {
  if val.eq(val.VInt(3), val.VInt(3)) { 0 } else { 1 }
}

fn test_eq_int_diff() -> Int {
  if val.eq(val.VInt(1), val.VInt(2)) { 1 } else { 0 }
}

fn test_eq_int_float_widening() -> Int {
  if val.eq(val.VInt(3), val.VFloat(3.0)) { 0 } else { 1 }
}

fn test_lt_int() -> Int {
  if val.lt(val.VInt(1), val.VInt(2)) { 0 } else { 1 }
}

fn test_lt_null_is_lowest() -> Int {
  if val.lt(val.VNull, val.VInt(0)) { 0 } else { 1 }
}

fn test_parse_str_int() -> Int {
  match val.parse_str("42") {
    val.VInt(n) => if n == 42 { 0 } else { 1 }
    _ => 1
  }
}

fn test_parse_str_float() -> Int {
  match val.parse_str("3.14") {
    val.VFloat(_) => 0
    _ => 1
  }
}

fn test_parse_str_bool_true() -> Int {
  match val.parse_str("true") {
    val.VBool(b) => if b { 0 } else { 1 }
    _ => 1
  }
}

fn test_parse_str_bool_false() -> Int {
  match val.parse_str("false") {
    val.VBool(b) => if b { 1 } else { 0 }
    _ => 1
  }
}

fn test_parse_str_null() -> Int {
  match val.parse_str("null") {
    val.VNull => 0
    _ => 1
  }
}

fn test_parse_str_fallback() -> Int {
  match val.parse_str("hello world") {
    val.VStr(s) => if s == "hello world" { 0 } else { 1 }
    _ => 1
  }
}

fn test_as_float_int() -> Int {
  match val.as_float(val.VInt(3)) {
    Some(f) => if f == 3.0 { 0 } else { 1 }
    None => 1
  }
}

fn test_as_float_float() -> Int {
  match val.as_float(val.VFloat(2.5)) {
    Some(f) => if f == 2.5 { 0 } else { 1 }
    None => 1
  }
}

fn test_as_float_null() -> Int {
  match val.as_float(val.VNull) {
    Some(_) => 1
    None => 0
  }
}

fn test_as_float_str() -> Int {
  match val.as_float(val.VStr("hello")) {
    Some(_) => 1
    None => 0
  }
}

fn run_all() -> Int {
  test_vint_to_str() +
  test_vfloat_to_str() +
  test_vbool_to_str() +
  test_vstr_to_str() +
  test_vnull_to_str() +
  test_type_name_int() +
  test_type_name_float() +
  test_type_name_str() +
  test_type_name_bool() +
  test_type_name_null() +
  test_is_null_true() +
  test_is_null_false() +
  test_is_numeric_int() +
  test_is_numeric_float() +
  test_is_numeric_str() +
  test_eq_int_same() +
  test_eq_int_diff() +
  test_eq_int_float_widening() +
  test_lt_int() +
  test_lt_null_is_lowest() +
  test_parse_str_int() +
  test_parse_str_float() +
  test_parse_str_bool_true() +
  test_parse_str_bool_false() +
  test_parse_str_null() +
  test_parse_str_fallback() +
  test_as_float_int() +
  test_as_float_float() +
  test_as_float_null() +
  test_as_float_str()
}
