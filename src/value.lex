# Value ADT — every DataFrame cell holds one variant.
# VNull represents missing / unknown data.

import "std.str"   as str
import "std.int"   as int
import "std.float" as float

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
    VFloat(f) => float.to_str(f),
    VStr(s)   => s,
  }
}

fn type_name(v :: Value) -> Str {
  match v {
    VNull     => "Null",
    VBool(_)  => "Bool",
    VInt(_)   => "Int",
    VFloat(_) => "Float",
    VStr(_)   => "Str",
  }
}

fn is_null(v :: Value) -> Bool {
  match v { VNull => true, _ => false }
}

fn is_numeric(v :: Value) -> Bool {
  match v { VInt(_) => true, VFloat(_) => true, _ => false }
}

fn as_float(v :: Value) -> Option[Float] {
  match v {
    VFloat(f) => Some(f),
    VInt(n)   => Some(int.to_float(n)),
    _         => None,
  }
}

fn as_int(v :: Value) -> Option[Int] {
  match v { VInt(n) => Some(n), _ => None }
}

# Structural equality with Int/Float widening.
fn eq(a :: Value, b :: Value) -> Bool {
  match a {
    VNull    => match b { VNull => true, _ => false },
    VBool(x) => match b { VBool(y) => x == y, _ => false },
    VStr(x)  => match b { VStr(y)  => x == y, _ => false },
    VInt(x)  => match b {
      VInt(y)   => x == y,
      VFloat(y) => int.to_float(x) == y,
      _         => false,
    },
    VFloat(x) => match b {
      VFloat(y) => x == y,
      VInt(y)   => x == int.to_float(y),
      _         => false,
    },
  }
}

# VNull sorts lowest; mismatched types fall back to type_name lexicographic order.
fn lt(a :: Value, b :: Value) -> Bool {
  match a {
    VNull => match b { VNull => false, _ => true },
    VInt(x) => match b {
      VNull     => false,
      VInt(y)   => x < y,
      VFloat(y) => int.to_float(x) < y,
      _         => type_name(a) < type_name(b),
    },
    VFloat(x) => match b {
      VNull     => false,
      VFloat(y) => x < y,
      VInt(y)   => x < int.to_float(y),
      _         => type_name(a) < type_name(b),
    },
    VStr(x) => match b {
      VNull   => false,
      VStr(y) => x < y,
      _       => type_name(a) < type_name(b),
    },
    VBool(x) => match b {
      VNull    => false,
      VBool(y) => if x { false } else { y },
      _        => type_name(a) < type_name(b),
    },
  }
}

fn lte(a :: Value, b :: Value) -> Bool { lt(a, b) or eq(a, b) }
fn gt(a :: Value, b :: Value)  -> Bool { lt(b, a) }
fn gte(a :: Value, b :: Value) -> Bool { lte(b, a) }

# Heuristic: try Int, then Float, then Bool, then null sentinel, else Str.
fn parse_str(s :: Str) -> Value {
  if s == "null" or s == "NULL" or s == "" {
    VNull
  } else if s == "true" {
    VBool(true)
  } else if s == "false" {
    VBool(false)
  } else {
    match str.to_int(s) {
      Some(n) => VInt(n),
      None    => match str.to_float(s) {
        Some(f) => VFloat(f),
        None    => VStr(s),
      },
    }
  }
}
