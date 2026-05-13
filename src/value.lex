# lex-frame — cell Value ADT
#
# Every DataFrame cell holds one of five variants. VNull signals a
# missing value. As-float / as-int conversions are total (returning
# Option) so downstream aggregations never crash on type mismatches.
# All functions are pure; no effects.

import "std.str"   as str
import "std.int"   as int
import "std.float" as float
import "std.list"  as list

type Value =
    VNull
  | VBool(Bool)
  | VInt(Int)
  | VFloat(Float)
  | VStr(Str)

fn to_str(v :: Value) -> Str {
  match v {
    VNull     => "null",
    VBool(b)  => if b { "true" } else { "false" },
    VInt(n)   => int.to_str(n),
    VFloat(x) => float.to_str(x),
    VStr(s)   => s,
  }
}

fn type_name(v :: Value) -> Str {
  match v {
    VNull     => "null",
    VBool(_)  => "bool",
    VInt(_)   => "int",
    VFloat(_) => "float",
    VStr(_)   => "str",
  }
}

fn is_null(v :: Value) -> Bool {
  match v { VNull => true, _ => false }
}

fn is_numeric(v :: Value) -> Bool {
  match v { VInt(_) => true, VFloat(_) => true, _ => false }
}

# int.to_float is available in lex >= 0.8.x
fn as_float(v :: Value) -> Option[Float] {
  match v {
    VFloat(x) => Some(x),
    VInt(n)   => Some(int.to_float(n)),
    _         => None,
  }
}

fn as_int(v :: Value) -> Option[Int] {
  match v { VInt(n) => Some(n), _ => None }
}

fn as_bool(v :: Value) -> Option[Bool] {
  match v { VBool(b) => Some(b), _ => None }
}

fn as_str_val(v :: Value) -> Option[Str] {
  match v { VStr(s) => Some(s), _ => None }
}

# Equality — mixed Int/Float widens to Float.
fn eq(a :: Value, b :: Value) -> Bool {
  match (a, b) {
    (VNull,     VNull)     => true,
    (VBool(x),  VBool(y))  => x == y,
    (VInt(x),   VInt(y))   => x == y,
    (VFloat(x), VFloat(y)) => x == y,
    (VStr(x),   VStr(y))   => x == y,
    (VInt(x),   VFloat(y)) => int.to_float(x) == y,
    (VFloat(x), VInt(y))   => x == int.to_float(y),
    _                      => false,
  }
}

# Ordering — VNull sorts lowest; mixed numeric widens to Float.
fn lt(a :: Value, b :: Value) -> Bool {
  match (a, b) {
    (VNull,     VNull)     => false,
    (VNull,     _)         => true,
    (_,         VNull)     => false,
    (VInt(x),   VInt(y))   => x < y,
    (VFloat(x), VFloat(y)) => x < y,
    (VInt(x),   VFloat(y)) => int.to_float(x) < y,
    (VFloat(x), VInt(y))   => x < int.to_float(y),
    (VStr(x),   VStr(y))   => x < y,
    (VBool(x),  VBool(y))  => if x { false } else { y },
    _                      => false,
  }
}

fn lte(a :: Value, b :: Value) -> Bool { eq(a, b) or lt(a, b) }
fn gt(a :: Value, b :: Value)  -> Bool { lt(b, a) }
fn gte(a :: Value, b :: Value) -> Bool { lte(b, a) }

# Heuristic parse: int → float → bool → str.
# Used by CSV readers and agent payload parsers.
fn parse_str(s :: Str) -> Value {
  let t := str.trim(s)
  if t == "" or t == "null" { VNull }
  else if t == "true"  { VBool(true)  }
  else if t == "false" { VBool(false) }
  else {
    match str.to_int(t) {
      Some(n) => VInt(n),
      None    => match str.to_float(t) {
        Some(x) => VFloat(x),
        None    => VStr(t),
      },
    }
  }
}
