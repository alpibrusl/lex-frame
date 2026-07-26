# Column / row transforms using lex-frame's dist module

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "std.math" as math

import "../src/value" as val

import "../src/frame" as frame

import "../src/dist" as dist

import "../src/inspect" as inspect

fn make_large_df() -> frame.DataFrame {
  let a := list.cons(val.vfloat(1.0), list.cons(val.vfloat(4.0), list.cons(val.vfloat(9.0), list.cons(val.vfloat(16.0), list.cons(val.vfloat(25.0), list.cons(val.vfloat(36.0), []))))))
  let b := list.cons(val.vint(10), list.cons(val.vint(20), list.cons(val.vint(30), list.cons(val.vint(40), list.cons(val.vint(50), list.cons(val.vint(60), []))))))
  let cols := list.cons(("a", a), list.cons(("b", b), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

# Apply sqrt to every value in the "a" column
fn demo_apply_col() -> Str {
  let sqrt_fn := fn (v :: val.Value) -> val.Value {
    match val.as_float(v) {
      Some(f) => val.vfloat(math.sqrt(f)),
      None => v,
    }
  }
  match dist.par_apply_col(make_large_df(), "a", sqrt_fn) {
    Err(e) => str.concat("Error: ", e.message),
    Ok(out) => inspect.to_markdown(out, 10),
  }
}

# Apply a transform to every column
fn demo_apply_all() -> Str {
  let double_fn := fn (name :: Str, xs :: List[val.Value]) -> List[val.Value] {
    list.map(xs, fn (v :: val.Value) -> val.Value {
      match val.as_int(v) {
        Some(n) => val.vint(n * 2),
        None => match val.as_float(v) {
          Some(f) => val.vfloat(f * 2.0),
          None => v,
        },
      }
    })
  }
  inspect.to_markdown(dist.par_apply_all_cols(make_large_df(), double_fn), 10)
}

# Filter rows through the row API
fn demo_filter() -> Str {
  let pred := fn (row :: List[(Str, val.Value)]) -> Bool {
    list.fold(row, false, fn (acc :: Bool, pair :: (Str, val.Value)) -> Bool {
      acc or match pair {
        (k, v) => k == "b" and match val.as_int(v) {
          Some(n) => n > 30,
          None => false,
        },
      }
    })
  }
  inspect.to_markdown(dist.par_filter_rows(make_large_df(), "b > 30", pred), 10)
}

# Estimate whether chunking work is worthwhile before committing
fn demo_cost_estimate() -> Str {
  str.concat("Estimated cost score: ", int.to_str(dist.estimate_par_cost(make_large_df())))
}

fn main() -> Str {
  str.concat(demo_apply_col(), str.concat("\n\n", str.concat(demo_apply_all(), str.concat("\n\n", str.concat(demo_filter(), str.concat("\n\n", demo_cost_estimate()))))))
}

