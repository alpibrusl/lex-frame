# lex-frame — typed column storage
#
# Col replaces List[Value] as the per-column representation.
# Each variant holds a plain List of the native Lex type so that
# aggregations operate on unboxed values (no per-cell variant dispatch).
#
# Rule: only this file pattern-matches on Col constructors. All other
# modules call the functions below instead.

import "std.list"  as list
import "std.map"   as map
import "std.str"   as str
import "std.int"   as int
import "std.float" as float
import "std.math"  as math
import "./value"   as val

type Col =
    IntCol(List[Int])
  | FloatCol(List[Float])
  | StrCol(List[Str])
  | BoolCol(List[Bool])
  | NullableInt(List[Option[Int]])
  | NullableFloat(List[Option[Float]])
  | NullableStr(List[Option[Str]])
  | NullableBool(List[Option[Bool]])

# ---- constructors ---------------------------------------------------

fn col_int(xs :: List[Int]) -> Col           { IntCol(xs) }
fn col_float(xs :: List[Float]) -> Col       { FloatCol(xs) }
fn col_str(xs :: List[Str]) -> Col           { StrCol(xs) }
fn col_bool(xs :: List[Bool]) -> Col         { BoolCol(xs) }
fn col_nullable_int(xs :: List[Option[Int]]) -> Col     { NullableInt(xs) }
fn col_nullable_float(xs :: List[Option[Float]]) -> Col { NullableFloat(xs) }
fn col_nullable_str(xs :: List[Option[Str]]) -> Col     { NullableStr(xs) }
fn col_nullable_bool(xs :: List[Option[Bool]]) -> Col   { NullableBool(xs) }

# ---- type name ------------------------------------------------------

fn col_type_name(c :: Col) -> Str {
  match c {
    IntCol(_)       => "Int",
    FloatCol(_)     => "Float",
    StrCol(_)       => "Str",
    BoolCol(_)      => "Bool",
    NullableInt(_)  => "Int?",
    NullableFloat(_)=> "Float?",
    NullableStr(_)  => "Str?",
    NullableBool(_) => "Bool?",
  }
}

fn col_is_nullable(c :: Col) -> Bool {
  match c {
    NullableInt(_)  => true,
    NullableFloat(_)=> true,
    NullableStr(_)  => true,
    NullableBool(_) => true,
    _               => false,
  }
}

# ---- length ---------------------------------------------------------

fn col_len(c :: Col) -> Int {
  match c {
    IntCol(xs)       => list.len(xs),
    FloatCol(xs)     => list.len(xs),
    StrCol(xs)       => list.len(xs),
    BoolCol(xs)      => list.len(xs),
    NullableInt(xs)  => list.len(xs),
    NullableFloat(xs)=> list.len(xs),
    NullableStr(xs)  => list.len(xs),
    NullableBool(xs) => list.len(xs),
  }
}

# ---- element access (returns Value for cross-type row ops) ----------

fn col_nth(c :: Col, i :: Int) -> val.Value {
  match c {
    IntCol(xs)       => nth_int(xs, i),
    FloatCol(xs)     => nth_float(xs, i),
    StrCol(xs)       => nth_str(xs, i),
    BoolCol(xs)      => nth_bool(xs, i),
    NullableInt(xs)  => nth_opt_int(xs, i),
    NullableFloat(xs)=> nth_opt_float(xs, i),
    NullableStr(xs)  => nth_opt_str(xs, i),
    NullableBool(xs) => nth_opt_bool(xs, i),
  }
}

fn nth_int(xs :: List[Int], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Int], p :: (Int, Int)) -> Map[Str, Int] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) {
    Some(v) => val.vint(v),
    None    => val.vnull(),
  }
}

fn nth_float(xs :: List[Float], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Float], p :: (Int, Float)) -> Map[Str, Float] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) {
    Some(v) => val.vfloat(v),
    None    => val.vnull(),
  }
}

fn nth_str(xs :: List[Str], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Str], p :: (Int, Str)) -> Map[Str, Str] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) {
    Some(v) => val.vstr(v),
    None    => val.vnull(),
  }
}

fn nth_bool(xs :: List[Bool], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Bool], p :: (Int, Bool)) -> Map[Str, Bool] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) {
    Some(v) => val.vbool(v),
    None    => val.vnull(),
  }
}

fn nth_opt_int(xs :: List[Option[Int]], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Option[Int]], p :: (Int, Option[Int])) -> Map[Str, Option[Int]] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) {
    None         => val.vnull(),
    Some(opt)    => match opt { None => val.vnull(), Some(n) => val.vint(n) },
  }
}

fn nth_opt_float(xs :: List[Option[Float]], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Option[Float]], p :: (Int, Option[Float])) -> Map[Str, Option[Float]] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) {
    None         => val.vnull(),
    Some(opt)    => match opt { None => val.vnull(), Some(f) => val.vfloat(f) },
  }
}

fn nth_opt_str(xs :: List[Option[Str]], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Option[Str]], p :: (Int, Option[Str])) -> Map[Str, Option[Str]] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) {
    None         => val.vnull(),
    Some(opt)    => match opt { None => val.vnull(), Some(s) => val.vstr(s) },
  }
}

fn nth_opt_bool(xs :: List[Option[Bool]], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Option[Bool]], p :: (Int, Option[Bool])) -> Map[Str, Option[Bool]] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) {
    None         => val.vnull(),
    Some(opt)    => match opt { None => val.vnull(), Some(b) => val.vbool(b) },
  }
}

# ---- conversion: List[Value] <-> Col --------------------------------

# Infer a typed Col from a List[Value]. Scans once for type, then converts.
fn col_from_values(vs :: List[val.Value]) -> Col {
  let info := scan_value_types(vs)
  let has_null  := match info { (a, _, _, _, _, _) => a }
  let has_int   := match info { (_, b, _, _, _, _) => b }
  let has_float := match info { (_, _, c, _, _, _) => c }
  let has_bool  := match info { (_, _, _, d, _, _) => d }
  let has_str   := match info { (_, _, _, _, e, _) => e }
  let has_other := match info { (_, _, _, _, _, f) => f }
  if has_bool and not has_int and not has_float and not has_str and not has_other {
    if has_null {
      NullableBool(list.map(vs, fn (v :: val.Value) -> Option[Bool] {
        if val.is_null(v) { None }
        else { match val.as_bool(v) { Some(b) => Some(b), None => None } }
      }))
    } else {
      BoolCol(list.map(vs, fn (v :: val.Value) -> Bool {
        match val.as_bool(v) { Some(b) => b, None => false }
      }))
    }
  } else {
    if has_int and not has_float and not has_str and not has_bool and not has_other {
      if has_null {
        NullableInt(list.map(vs, fn (v :: val.Value) -> Option[Int] {
          if val.is_null(v) { None }
          else { match val.as_int(v) { Some(n) => Some(n), None => None } }
        }))
      } else {
        IntCol(list.map(vs, fn (v :: val.Value) -> Int {
          match val.as_int(v) { Some(n) => n, None => 0 }
        }))
      }
    } else {
      if (has_int or has_float) and not has_str and not has_bool and not has_other {
        if has_null {
          NullableFloat(list.map(vs, fn (v :: val.Value) -> Option[Float] {
            if val.is_null(v) { None }
            else { match val.as_float(v) { Some(f) => Some(f), None => None } }
          }))
        } else {
          FloatCol(list.map(vs, fn (v :: val.Value) -> Float {
            match val.as_float(v) { Some(f) => f, None => 0.0 }
          }))
        }
      } else {
        if has_null {
          NullableStr(list.map(vs, fn (v :: val.Value) -> Option[Str] {
            if val.is_null(v) { None }
            else { Some(val.to_str(v)) }
          }))
        } else {
          StrCol(list.map(vs, fn (v :: val.Value) -> Str { val.to_str(v) }))
        }
      }
    }
  }
}

# Returns (has_null, has_int, has_float, has_bool, has_str, has_other)
fn scan_value_types(vs :: List[val.Value]) -> (Bool, Bool, Bool, Bool, Bool, Bool) {
  list.fold(vs, (false, false, false, false, false, false),
    fn (acc :: (Bool, Bool, Bool, Bool, Bool, Bool), v :: val.Value) -> (Bool, Bool, Bool, Bool, Bool, Bool) {
      let hn := match acc { (a, _, _, _, _, _) => a }
      let hi := match acc { (_, b, _, _, _, _) => b }
      let hf := match acc { (_, _, c, _, _, _) => c }
      let hb := match acc { (_, _, _, d, _, _) => d }
      let hs := match acc { (_, _, _, _, e, _) => e }
      let ho := match acc { (_, _, _, _, _, f) => f }
      let t  := val.type_name(v)
      if t == "Null"  { (true, hi, hf, hb, hs, ho) }
      else {
        if t == "Int"   { (hn, true, hf, hb, hs, ho) }
        else {
          if t == "Float" { (hn, hi, true, hb, hs, ho) }
          else {
            if t == "Bool"  { (hn, hi, hf, true, hs, ho) }
            else {
              if t == "Str"   { (hn, hi, hf, hb, true, ho) }
              else            { (hn, hi, hf, hb, hs, true) }
            }
          }
        }
      }
    })
}

# Convert a Col back to List[Value] (for row-level ops and I/O).
fn col_to_values(c :: Col) -> List[val.Value] {
  match c {
    IntCol(xs)       => list.map(xs, fn (n :: Int) -> val.Value { val.vint(n) }),
    FloatCol(xs)     => list.map(xs, fn (f :: Float) -> val.Value { val.vfloat(f) }),
    StrCol(xs)       => list.map(xs, fn (s :: Str) -> val.Value { val.vstr(s) }),
    BoolCol(xs)      => list.map(xs, fn (b :: Bool) -> val.Value { val.vbool(b) }),
    NullableInt(xs)  => list.map(xs, fn (o :: Option[Int]) -> val.Value {
      match o { None => val.vnull(), Some(n) => val.vint(n) }
    }),
    NullableFloat(xs)=> list.map(xs, fn (o :: Option[Float]) -> val.Value {
      match o { None => val.vnull(), Some(f) => val.vfloat(f) }
    }),
    NullableStr(xs)  => list.map(xs, fn (o :: Option[Str]) -> val.Value {
      match o { None => val.vnull(), Some(s) => val.vstr(s) }
    }),
    NullableBool(xs) => list.map(xs, fn (o :: Option[Bool]) -> val.Value {
      match o { None => val.vnull(), Some(b) => val.vbool(b) }
    }),
  }
}

# ---- filter by boolean mask -----------------------------------------

fn col_filter(c :: Col, mask :: List[Bool]) -> Col {
  match c {
    IntCol(xs)       => IntCol(filter_with_mask_int(xs, mask)),
    FloatCol(xs)     => FloatCol(filter_with_mask_float(xs, mask)),
    StrCol(xs)       => StrCol(filter_with_mask_str(xs, mask)),
    BoolCol(xs)      => BoolCol(filter_with_mask_bool(xs, mask)),
    NullableInt(xs)  => NullableInt(filter_with_mask_opt_int(xs, mask)),
    NullableFloat(xs)=> NullableFloat(filter_with_mask_opt_float(xs, mask)),
    NullableStr(xs)  => NullableStr(filter_with_mask_opt_str(xs, mask)),
    NullableBool(xs) => NullableBool(filter_with_mask_opt_bool(xs, mask)),
  }
}

fn filter_with_mask_int(xs :: List[Int], mask :: List[Bool]) -> List[Int] {
  let pairs := list.fold(list.enumerate(xs), [],
    fn (acc :: List[Int], p :: (Int, Int)) -> List[Int] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      let keep := nth_bool_list(mask, i)
      if keep { list.cons(v, acc) } else { acc }
    })
  list.reverse(pairs)
}

fn filter_with_mask_float(xs :: List[Float], mask :: List[Bool]) -> List[Float] {
  let pairs := list.fold(list.enumerate(xs), [],
    fn (acc :: List[Float], p :: (Int, Float)) -> List[Float] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      let keep := nth_bool_list(mask, i)
      if keep { list.cons(v, acc) } else { acc }
    })
  list.reverse(pairs)
}

fn filter_with_mask_str(xs :: List[Str], mask :: List[Bool]) -> List[Str] {
  let pairs := list.fold(list.enumerate(xs), [],
    fn (acc :: List[Str], p :: (Int, Str)) -> List[Str] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      let keep := nth_bool_list(mask, i)
      if keep { list.cons(v, acc) } else { acc }
    })
  list.reverse(pairs)
}

fn filter_with_mask_bool(xs :: List[Bool], mask :: List[Bool]) -> List[Bool] {
  let pairs := list.fold(list.enumerate(xs), [],
    fn (acc :: List[Bool], p :: (Int, Bool)) -> List[Bool] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      let keep := nth_bool_list(mask, i)
      if keep { list.cons(v, acc) } else { acc }
    })
  list.reverse(pairs)
}

fn filter_with_mask_opt_int(xs :: List[Option[Int]], mask :: List[Bool]) -> List[Option[Int]] {
  let pairs := list.fold(list.enumerate(xs), [],
    fn (acc :: List[Option[Int]], p :: (Int, Option[Int])) -> List[Option[Int]] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      let keep := nth_bool_list(mask, i)
      if keep { list.cons(v, acc) } else { acc }
    })
  list.reverse(pairs)
}

fn filter_with_mask_opt_float(xs :: List[Option[Float]], mask :: List[Bool]) -> List[Option[Float]] {
  let pairs := list.fold(list.enumerate(xs), [],
    fn (acc :: List[Option[Float]], p :: (Int, Option[Float])) -> List[Option[Float]] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      let keep := nth_bool_list(mask, i)
      if keep { list.cons(v, acc) } else { acc }
    })
  list.reverse(pairs)
}

fn filter_with_mask_opt_str(xs :: List[Option[Str]], mask :: List[Bool]) -> List[Option[Str]] {
  let pairs := list.fold(list.enumerate(xs), [],
    fn (acc :: List[Option[Str]], p :: (Int, Option[Str])) -> List[Option[Str]] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      let keep := nth_bool_list(mask, i)
      if keep { list.cons(v, acc) } else { acc }
    })
  list.reverse(pairs)
}

fn filter_with_mask_opt_bool(xs :: List[Option[Bool]], mask :: List[Bool]) -> List[Option[Bool]] {
  let pairs := list.fold(list.enumerate(xs), [],
    fn (acc :: List[Option[Bool]], p :: (Int, Option[Bool])) -> List[Option[Bool]] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      let keep := nth_bool_list(mask, i)
      if keep { list.cons(v, acc) } else { acc }
    })
  list.reverse(pairs)
}

# Helper: get bool at index i from a List[Bool] (O(n) via map).
fn nth_bool_list(xs :: List[Bool], i :: Int) -> Bool {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Bool], p :: (Int, Bool)) -> Map[Str, Bool] {
      let idx := match p { (a, _) => a }
      let v   := match p { (_, b) => b }
      map.set(acc, str.from_int(idx), v)
    })
  match map.get(m, str.from_int(i)) { Some(b) => b, None => false }
}

# ---- pick rows by index list ----------------------------------------

fn col_pick(c :: Col, indices :: List[Int]) -> Col {
  match c {
    IntCol(xs)       => IntCol(pick_int_list(xs, indices)),
    FloatCol(xs)     => FloatCol(pick_float_list(xs, indices)),
    StrCol(xs)       => StrCol(pick_str_list(xs, indices)),
    BoolCol(xs)      => BoolCol(pick_bool_list(xs, indices)),
    NullableInt(xs)  => NullableInt(pick_opt_int_list(xs, indices)),
    NullableFloat(xs)=> NullableFloat(pick_opt_float_list(xs, indices)),
    NullableStr(xs)  => NullableStr(pick_opt_str_list(xs, indices)),
    NullableBool(xs) => NullableBool(pick_opt_bool_list(xs, indices)),
  }
}

fn pick_int_list(xs :: List[Int], indices :: List[Int]) -> List[Int] {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Int], p :: (Int, Int)) -> Map[Str, Int] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      map.set(acc, str.from_int(i), v)
    })
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Int], i :: Int) -> List[Int] {
      match map.get(m, str.from_int(i)) { Some(v) => list.cons(v, acc), None => acc }
    }))
}

fn pick_float_list(xs :: List[Float], indices :: List[Int]) -> List[Float] {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Float], p :: (Int, Float)) -> Map[Str, Float] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      map.set(acc, str.from_int(i), v)
    })
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Float], i :: Int) -> List[Float] {
      match map.get(m, str.from_int(i)) { Some(v) => list.cons(v, acc), None => acc }
    }))
}

fn pick_str_list(xs :: List[Str], indices :: List[Int]) -> List[Str] {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Str], p :: (Int, Str)) -> Map[Str, Str] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      map.set(acc, str.from_int(i), v)
    })
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Str], i :: Int) -> List[Str] {
      match map.get(m, str.from_int(i)) { Some(v) => list.cons(v, acc), None => acc }
    }))
}

fn pick_bool_list(xs :: List[Bool], indices :: List[Int]) -> List[Bool] {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Bool], p :: (Int, Bool)) -> Map[Str, Bool] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      map.set(acc, str.from_int(i), v)
    })
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Bool], i :: Int) -> List[Bool] {
      match map.get(m, str.from_int(i)) { Some(v) => list.cons(v, acc), None => acc }
    }))
}

fn pick_opt_int_list(xs :: List[Option[Int]], indices :: List[Int]) -> List[Option[Int]] {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Option[Int]], p :: (Int, Option[Int])) -> Map[Str, Option[Int]] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      map.set(acc, str.from_int(i), v)
    })
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Option[Int]], i :: Int) -> List[Option[Int]] {
      match map.get(m, str.from_int(i)) { Some(v) => list.cons(v, acc), None => list.cons(None, acc) }
    }))
}

fn pick_opt_float_list(xs :: List[Option[Float]], indices :: List[Int]) -> List[Option[Float]] {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Option[Float]], p :: (Int, Option[Float])) -> Map[Str, Option[Float]] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      map.set(acc, str.from_int(i), v)
    })
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Option[Float]], i :: Int) -> List[Option[Float]] {
      match map.get(m, str.from_int(i)) { Some(v) => list.cons(v, acc), None => list.cons(None, acc) }
    }))
}

fn pick_opt_str_list(xs :: List[Option[Str]], indices :: List[Int]) -> List[Option[Str]] {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Option[Str]], p :: (Int, Option[Str])) -> Map[Str, Option[Str]] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      map.set(acc, str.from_int(i), v)
    })
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Option[Str]], i :: Int) -> List[Option[Str]] {
      match map.get(m, str.from_int(i)) { Some(v) => list.cons(v, acc), None => list.cons(None, acc) }
    }))
}

fn pick_opt_bool_list(xs :: List[Option[Bool]], indices :: List[Int]) -> List[Option[Bool]] {
  let m := list.fold(list.enumerate(xs), map.new(),
    fn (acc :: Map[Str, Option[Bool]], p :: (Int, Option[Bool])) -> Map[Str, Option[Bool]] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      map.set(acc, str.from_int(i), v)
    })
  list.reverse(list.fold(indices, [],
    fn (acc :: List[Option[Bool]], i :: Int) -> List[Option[Bool]] {
      match map.get(m, str.from_int(i)) { Some(v) => list.cons(v, acc), None => list.cons(None, acc) }
    }))
}

# ---- concatenate two columns ----------------------------------------

fn col_concat(a :: Col, b :: Col) -> Col {
  match a {
    IntCol(xs) =>
      match b {
        IntCol(ys)       => IntCol(list.concat(xs, ys)),
        NullableInt(ys)  => NullableInt(list.concat(
          list.map(xs, fn (n :: Int) -> Option[Int] { Some(n) }), ys)),
        _                => StrCol(list.concat(col_to_str_list(a), col_to_str_list(b))),
      },
    FloatCol(xs) =>
      match b {
        FloatCol(ys)     => FloatCol(list.concat(xs, ys)),
        NullableFloat(ys)=> NullableFloat(list.concat(
          list.map(xs, fn (f :: Float) -> Option[Float] { Some(f) }), ys)),
        _                => StrCol(list.concat(col_to_str_list(a), col_to_str_list(b))),
      },
    StrCol(xs) =>
      match b {
        StrCol(ys)       => StrCol(list.concat(xs, ys)),
        NullableStr(ys)  => NullableStr(list.concat(
          list.map(xs, fn (s :: Str) -> Option[Str] { Some(s) }), ys)),
        _                => StrCol(list.concat(col_to_str_list(a), col_to_str_list(b))),
      },
    BoolCol(xs) =>
      match b {
        BoolCol(ys)      => BoolCol(list.concat(xs, ys)),
        NullableBool(ys) => NullableBool(list.concat(
          list.map(xs, fn (bv :: Bool) -> Option[Bool] { Some(bv) }), ys)),
        _                => StrCol(list.concat(col_to_str_list(a), col_to_str_list(b))),
      },
    NullableInt(xs) =>
      match b {
        NullableInt(ys) => NullableInt(list.concat(xs, ys)),
        IntCol(ys)      => NullableInt(list.concat(xs,
          list.map(ys, fn (n :: Int) -> Option[Int] { Some(n) }))),
        _               => StrCol(list.concat(col_to_str_list(a), col_to_str_list(b))),
      },
    NullableFloat(xs) =>
      match b {
        NullableFloat(ys) => NullableFloat(list.concat(xs, ys)),
        FloatCol(ys)      => NullableFloat(list.concat(xs,
          list.map(ys, fn (f :: Float) -> Option[Float] { Some(f) }))),
        _                 => StrCol(list.concat(col_to_str_list(a), col_to_str_list(b))),
      },
    NullableStr(xs) =>
      match b {
        NullableStr(ys) => NullableStr(list.concat(xs, ys)),
        StrCol(ys)      => NullableStr(list.concat(xs,
          list.map(ys, fn (s :: Str) -> Option[Str] { Some(s) }))),
        _               => StrCol(list.concat(col_to_str_list(a), col_to_str_list(b))),
      },
    NullableBool(xs) =>
      match b {
        NullableBool(ys) => NullableBool(list.concat(xs, ys)),
        BoolCol(ys)      => NullableBool(list.concat(xs,
          list.map(ys, fn (bv :: Bool) -> Option[Bool] { Some(bv) }))),
        _                => StrCol(list.concat(col_to_str_list(a), col_to_str_list(b))),
      },
  }
}

fn col_to_str_list(c :: Col) -> List[Str] {
  list.map(col_to_values(c), fn (v :: val.Value) -> Str { val.to_str(v) })
}

# ---- null operations ------------------------------------------------

fn col_null_count(c :: Col) -> Int {
  match c {
    NullableInt(xs)  => count_nones_int(xs),
    NullableFloat(xs)=> count_nones_float(xs),
    NullableStr(xs)  => count_nones_str(xs),
    NullableBool(xs) => count_nones_bool(xs),
    _                => 0,
  }
}

fn count_nones_int(xs :: List[Option[Int]]) -> Int {
  list.fold(xs, 0, fn (acc :: Int, o :: Option[Int]) -> Int {
    match o { None => acc + 1, Some(_) => acc }
  })
}

fn count_nones_float(xs :: List[Option[Float]]) -> Int {
  list.fold(xs, 0, fn (acc :: Int, o :: Option[Float]) -> Int {
    match o { None => acc + 1, Some(_) => acc }
  })
}

fn count_nones_str(xs :: List[Option[Str]]) -> Int {
  list.fold(xs, 0, fn (acc :: Int, o :: Option[Str]) -> Int {
    match o { None => acc + 1, Some(_) => acc }
  })
}

fn count_nones_bool(xs :: List[Option[Bool]]) -> Int {
  list.fold(xs, 0, fn (acc :: Int, o :: Option[Bool]) -> Int {
    match o { None => acc + 1, Some(_) => acc }
  })
}

fn col_non_null_count(c :: Col) -> Int {
  col_len(c) - col_null_count(c)
}

# ---- aggregations ---------------------------------------------------

fn col_sum(c :: Col) -> Option[val.Value] {
  match c {
    IntCol(xs) => {
      if list.len(xs) == 0 { None }
      else { Some(val.vint(list.fold(xs, 0, fn (acc :: Int, x :: Int) -> Int { acc + x }))) }
    },
    FloatCol(xs) => {
      if list.len(xs) == 0 { None }
      else { Some(val.vfloat(list.fold(xs, 0.0, fn (acc :: Float, x :: Float) -> Float { acc + x }))) }
    },
    NullableInt(xs) => {
      let r := list.fold(xs, (0, 0),
        fn (acc :: (Int, Int), o :: Option[Int]) -> (Int, Int) {
          let s := match acc { (a, _) => a }
          let n := match acc { (_, b) => b }
          match o { None => (s, n), Some(v) => (s + v, n + 1) }
        })
      let count := match r { (_, b) => b }
      if count == 0 { None }
      else { Some(val.vint(match r { (a, _) => a })) }
    },
    NullableFloat(xs) => {
      let r := list.fold(xs, (0.0, 0),
        fn (acc :: (Float, Int), o :: Option[Float]) -> (Float, Int) {
          let s := match acc { (a, _) => a }
          let n := match acc { (_, b) => b }
          match o { None => (s, n), Some(v) => (s + v, n + 1) }
        })
      let count := match r { (_, b) => b }
      if count == 0 { None }
      else { Some(val.vfloat(match r { (a, _) => a })) }
    },
    _ => None,
  }
}

fn col_mean(c :: Col) -> Option[Float] {
  match c {
    IntCol(xs) => {
      let n := list.len(xs)
      if n == 0 { None }
      else {
        let s := list.fold(xs, 0, fn (acc :: Int, x :: Int) -> Int { acc + x })
        Some(int.to_float(s) / int.to_float(n))
      }
    },
    FloatCol(xs) => {
      let n := list.len(xs)
      if n == 0 { None }
      else {
        let s := list.fold(xs, 0.0, fn (acc :: Float, x :: Float) -> Float { acc + x })
        Some(s / int.to_float(n))
      }
    },
    NullableInt(xs) => {
      let r := list.fold(xs, (0, 0),
        fn (acc :: (Int, Int), o :: Option[Int]) -> (Int, Int) {
          let s := match acc { (a, _) => a }
          let n := match acc { (_, b) => b }
          match o { None => (s, n), Some(v) => (s + v, n + 1) }
        })
      let count := match r { (_, b) => b }
      if count == 0 { None }
      else { Some(int.to_float(match r { (a, _) => a }) / int.to_float(count)) }
    },
    NullableFloat(xs) => {
      let r := list.fold(xs, (0.0, 0),
        fn (acc :: (Float, Int), o :: Option[Float]) -> (Float, Int) {
          let s := match acc { (a, _) => a }
          let n := match acc { (_, b) => b }
          match o { None => (s, n), Some(v) => (s + v, n + 1) }
        })
      let count := match r { (_, b) => b }
      if count == 0 { None }
      else { Some(match r { (a, _) => a } / int.to_float(count)) }
    },
    _ => None,
  }
}

fn col_min(c :: Col) -> Option[val.Value] {
  match c {
    IntCol(xs) => {
      match list.head(xs) {
        None    => None,
        Some(h) => Some(val.vint(list.fold(xs, h, fn (acc :: Int, x :: Int) -> Int {
          if x < acc { x } else { acc }
        }))),
      }
    },
    FloatCol(xs) => {
      match list.head(xs) {
        None    => None,
        Some(h) => Some(val.vfloat(list.fold(xs, h, fn (acc :: Float, x :: Float) -> Float {
          if x < acc { x } else { acc }
        }))),
      }
    },
    StrCol(xs) => {
      match list.head(xs) {
        None    => None,
        Some(h) => Some(val.vstr(list.fold(xs, h, fn (acc :: Str, x :: Str) -> Str {
          if x < acc { x } else { acc }
        }))),
      }
    },
    NullableInt(xs) => {
      let non_null := list.filter(xs, fn (o :: Option[Int]) -> Bool {
        match o { Some(_) => true, None => false }
      })
      match list.head(non_null) {
        None         => None,
        Some(first)  =>
          match first {
            None    => None,
            Some(h) => Some(val.vint(list.fold(non_null, h, fn (acc :: Int, o :: Option[Int]) -> Int {
              match o { None => acc, Some(x) => if x < acc { x } else { acc } }
            }))),
          },
      }
    },
    NullableFloat(xs) => {
      let non_null := list.filter(xs, fn (o :: Option[Float]) -> Bool {
        match o { Some(_) => true, None => false }
      })
      match list.head(non_null) {
        None         => None,
        Some(first)  =>
          match first {
            None    => None,
            Some(h) => Some(val.vfloat(list.fold(non_null, h, fn (acc :: Float, o :: Option[Float]) -> Float {
              match o { None => acc, Some(x) => if x < acc { x } else { acc } }
            }))),
          },
      }
    },
    NullableStr(xs) => {
      let non_null := list.filter(xs, fn (o :: Option[Str]) -> Bool {
        match o { Some(_) => true, None => false }
      })
      match list.head(non_null) {
        None         => None,
        Some(first)  =>
          match first {
            None    => None,
            Some(h) => Some(val.vstr(list.fold(non_null, h, fn (acc :: Str, o :: Option[Str]) -> Str {
              match o { None => acc, Some(x) => if x < acc { x } else { acc } }
            }))),
          },
      }
    },
    _ => None,
  }
}

fn col_max(c :: Col) -> Option[val.Value] {
  match c {
    IntCol(xs) => {
      match list.head(xs) {
        None    => None,
        Some(h) => Some(val.vint(list.fold(xs, h, fn (acc :: Int, x :: Int) -> Int {
          if x > acc { x } else { acc }
        }))),
      }
    },
    FloatCol(xs) => {
      match list.head(xs) {
        None    => None,
        Some(h) => Some(val.vfloat(list.fold(xs, h, fn (acc :: Float, x :: Float) -> Float {
          if x > acc { x } else { acc }
        }))),
      }
    },
    StrCol(xs) => {
      match list.head(xs) {
        None    => None,
        Some(h) => Some(val.vstr(list.fold(xs, h, fn (acc :: Str, x :: Str) -> Str {
          if x > acc { x } else { acc }
        }))),
      }
    },
    NullableInt(xs) => {
      let non_null := list.filter(xs, fn (o :: Option[Int]) -> Bool {
        match o { Some(_) => true, None => false }
      })
      match list.head(non_null) {
        None         => None,
        Some(first)  =>
          match first {
            None    => None,
            Some(h) => Some(val.vint(list.fold(non_null, h, fn (acc :: Int, o :: Option[Int]) -> Int {
              match o { None => acc, Some(x) => if x > acc { x } else { acc } }
            }))),
          },
      }
    },
    NullableFloat(xs) => {
      let non_null := list.filter(xs, fn (o :: Option[Float]) -> Bool {
        match o { Some(_) => true, None => false }
      })
      match list.head(non_null) {
        None         => None,
        Some(first)  =>
          match first {
            None    => None,
            Some(h) => Some(val.vfloat(list.fold(non_null, h, fn (acc :: Float, o :: Option[Float]) -> Float {
              match o { None => acc, Some(x) => if x > acc { x } else { acc } }
            }))),
          },
      }
    },
    NullableStr(xs) => {
      let non_null := list.filter(xs, fn (o :: Option[Str]) -> Bool {
        match o { Some(_) => true, None => false }
      })
      match list.head(non_null) {
        None         => None,
        Some(first)  =>
          match first {
            None    => None,
            Some(h) => Some(val.vstr(list.fold(non_null, h, fn (acc :: Str, o :: Option[Str]) -> Str {
              match o { None => acc, Some(x) => if x > acc { x } else { acc } }
            }))),
          },
      }
    },
    _ => None,
  }
}

fn col_variance(c :: Col) -> Option[Float] {
  match col_mean(c) {
    None    => None,
    Some(m) => {
      let n := col_non_null_count(c)
      if n < 2 { None }
      else {
        let ss := match c {
          IntCol(xs) =>
            list.fold(xs, 0.0, fn (acc :: Float, x :: Int) -> Float {
              let d := int.to_float(x) - m
              acc + d * d
            }),
          FloatCol(xs) =>
            list.fold(xs, 0.0, fn (acc :: Float, x :: Float) -> Float {
              let d := x - m
              acc + d * d
            }),
          NullableInt(xs) =>
            list.fold(xs, 0.0, fn (acc :: Float, o :: Option[Int]) -> Float {
              match o { None => acc, Some(x) => let d := int.to_float(x) - m in acc + d * d }
            }),
          NullableFloat(xs) =>
            list.fold(xs, 0.0, fn (acc :: Float, o :: Option[Float]) -> Float {
              match o { None => acc, Some(x) => let d := x - m in acc + d * d }
            }),
          _ => 0.0,
        }
        Some(ss / int.to_float(n - 1))
      }
    },
  }
}

fn col_std(c :: Col) -> Option[Float] {
  match col_variance(c) {
    None    => None,
    Some(v) => Some(math.sqrt(v)),
  }
}

fn col_n_distinct(c :: Col) -> Int {
  match c {
    IntCol(xs) =>
      list.len(map.entries(list.fold(xs, map.new(),
        fn (m :: Map[Str, Bool], x :: Int) -> Map[Str, Bool] {
          map.set(m, str.from_int(x), true)
        }))),
    FloatCol(xs) =>
      list.len(map.entries(list.fold(xs, map.new(),
        fn (m :: Map[Str, Bool], x :: Float) -> Map[Str, Bool] {
          map.set(m, str.from_float(x), true)
        }))),
    StrCol(xs) =>
      list.len(map.entries(list.fold(xs, map.new(),
        fn (m :: Map[Str, Bool], x :: Str) -> Map[Str, Bool] {
          map.set(m, x, true)
        }))),
    BoolCol(xs) =>
      list.len(map.entries(list.fold(xs, map.new(),
        fn (m :: Map[Str, Bool], x :: Bool) -> Map[Str, Bool] {
          map.set(m, if x { "true" } else { "false" }, true)
        }))),
    NullableInt(xs) =>
      list.len(map.entries(list.fold(xs, map.new(),
        fn (m :: Map[Str, Bool], o :: Option[Int]) -> Map[Str, Bool] {
          match o { None => map.set(m, "null", true), Some(x) => map.set(m, str.from_int(x), true) }
        }))),
    NullableFloat(xs) =>
      list.len(map.entries(list.fold(xs, map.new(),
        fn (m :: Map[Str, Bool], o :: Option[Float]) -> Map[Str, Bool] {
          match o { None => map.set(m, "null", true), Some(x) => map.set(m, str.from_float(x), true) }
        }))),
    NullableStr(xs) =>
      list.len(map.entries(list.fold(xs, map.new(),
        fn (m :: Map[Str, Bool], o :: Option[Str]) -> Map[Str, Bool] {
          match o { None => map.set(m, "null", true), Some(x) => map.set(m, x, true) }
        }))),
    NullableBool(xs) =>
      list.len(map.entries(list.fold(xs, map.new(),
        fn (m :: Map[Str, Bool], o :: Option[Bool]) -> Map[Str, Bool] {
          match o { None => map.set(m, "null", true), Some(x) => map.set(m, if x { "true" } else { "false" }, true) }
        }))),
  }
}

# ---- element-wise key extraction (for join/group) -------------------

# Return string key for row i (used by join and group_by).
fn col_key_at(c :: Col, i :: Int) -> Str {
  val.to_str(col_nth(c, i))
}

# Return all string keys (used by group_by to build index map).
fn col_keys(c :: Col) -> List[Str] {
  list.map(col_to_values(c), fn (v :: val.Value) -> Str { val.to_str(v) })
}

# ---- append a single Value to a Col ---------------------------------

fn col_append(c :: Col, v :: val.Value) -> Col {
  col_concat(c, col_from_values(list.cons(v, [])))
}

# ---- create an empty Col of a given type name -----------------------

fn col_empty(type_name :: Str) -> Col {
  if type_name == "Int"    { IntCol([]) }
  else {
    if type_name == "Float"  { FloatCol([]) }
    else {
      if type_name == "Bool"   { BoolCol([]) }
      else {
        if type_name == "Int?"   { NullableInt([]) }
        else {
          if type_name == "Float?" { NullableFloat([]) }
          else {
            if type_name == "Bool?"  { NullableBool([]) }
            else {
              if type_name == "Str?"   { NullableStr([]) }
              else                     { StrCol([]) }
            }
          }
        }
      }
    }
  }
}
