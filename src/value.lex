import "std.str" as str

import "std.int" as int

import "std.float" as float

type Value = VNull | VBool(Bool) | VInt(Int) | VFloat(Float) | VStr(Str)

fn to_str(v :: Value) -> Str {
  match v {
    VNull => "null",
    VBool(b) => if b {
      "true"
    } else {
      "false"
    },
    VInt(n) => int.to_str(n),
    VFloat(f) => float.to_str(f),
    VStr(s) => s,
  }
}

fn type_name(v :: Value) -> Str {
  match v {
    VNull => "Null",
    VBool(_) => "Bool",
    VInt(_) => "Int",
    VFloat(_) => "Float",
    VStr(_) => "Str",
  }
}

fn is_null(v :: Value) -> Bool {
  match v {
    VNull => true,
    _ => false,
  }
}

fn is_numeric(v :: Value) -> Bool {
  match v {
    VInt(_) => true,
    VFloat(_) => true,
    _ => false,
  }
}

fn as_float(v :: Value) -> Option[Float] {
  match v {
    VFloat(f) => Some(f),
    VInt(n) => Some(int.to_float(n)),
    _ => None,
  }
}

fn as_int(v :: Value) -> Option[Int] {
  match v {
    VInt(n) => Some(n),
    _ => None,
  }
}

fn eq(a :: Value, b :: Value) -> Bool {
  match a {
    VNull => match b {
      VNull => true,
      _ => false,
    },
    VBool(x) => match b {
      VBool(y) => x == y,
      _ => false,
    },
    VStr(x) => match b {
      VStr(y) => x == y,
      _ => false,
    },
    VInt(x) => match b {
      VInt(y) => x == y,
      VFloat(y) => int.to_float(x) == y,
      _ => false,
    },
    VFloat(x) => match b {
      VFloat(y) => x == y,
      VInt(y) => x == int.to_float(y),
      _ => false,
    },
  }
}

fn lt(a :: Value, b :: Value) -> Bool {
  match a {
    VNull => match b {
      VNull => false,
      _ => true,
    },
    VInt(x) => match b {
      VNull => false,
      VInt(y) => x < y,
      VFloat(y) => int.to_float(x) < y,
      _ => type_name(a) < type_name(b),
    },
    VFloat(x) => match b {
      VNull => false,
      VFloat(y) => x < y,
      VInt(y) => x < int.to_float(y),
      _ => type_name(a) < type_name(b),
    },
    VStr(x) => match b {
      VNull => false,
      VStr(y) => x < y,
      _ => type_name(a) < type_name(b),
    },
    VBool(x) => match b {
      VNull => false,
      VBool(y) => if x {
        false
      } else {
        y
      },
      _ => type_name(a) < type_name(b),
    },
  }
}

fn lte(a :: Value, b :: Value) -> Bool {
  lt(a, b) or eq(a, b)
}

fn gt(a :: Value, b :: Value) -> Bool {
  lt(b, a)
}

fn gte(a :: Value, b :: Value) -> Bool {
  lte(b, a)
}

fn vnull() -> Value {
  VNull
}

fn vbool(b :: Bool) -> Value {
  VBool(b)
}

fn vint(n :: Int) -> Value {
  VInt(n)
}

fn vfloat(f :: Float) -> Value {
  VFloat(f)
}

fn vstr(s :: Str) -> Value {
  VStr(s)
}

fn as_bool(v :: Value) -> Option[Bool] {
  match v {
    VBool(b) => Some(b),
    _ => None,
  }
}

fn as_str(v :: Value) -> Option[Str] {
  match v {
    VStr(s) => Some(s),
    _ => None,
  }
}

fn parse_str(s :: Str) -> Value {
  if s == "null" or s == "NULL" or s == "" {
    VNull
  } else {
    if s == "true" {
      VBool(true)
    } else {
      if s == "false" {
        VBool(false)
      } else {
        match str.to_int(s) {
          Some(n) => VInt(n),
          None => match str.to_float(s) {
            Some(f) => VFloat(f),
            None => VStr(s),
          },
        }
      }
    }
  }
}

