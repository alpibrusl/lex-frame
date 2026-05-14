// Parallel column transforms using lex-frame's dist module
import "std.list" as list
import "std.str" as str
import "std.math" as math
import "src/value" as val
import "src/frame" as frame
import "src/dist" as dist
import "src/inspect" as inspect

fn make_large_df() -> frame.DataFrame {
  // Build a 6-row DataFrame with numeric columns to demonstrate par_apply
  let a    = list.cons(val.VFloat(1.0), list.cons(val.VFloat(4.0), list.cons(val.VFloat(9.0),
             list.cons(val.VFloat(16.0), list.cons(val.VFloat(25.0), list.cons(val.VFloat(36.0), []))))))
  let b    = list.cons(val.VInt(10), list.cons(val.VInt(20), list.cons(val.VInt(30),
             list.cons(val.VInt(40), list.cons(val.VInt(50), list.cons(val.VInt(60), []))))))
  let cols = list.cons(("a", a), list.cons(("b", b), []))
  match frame.from_columns(cols) {
    Ok(df) => df
    Err(_) => frame.empty()
  }
}

// Apply sqrt to every value in the "a" column in parallel
fn demo_par_apply_col() -> Str {
  let df        = make_large_df()
  let sqrt_fn   = fn(v :: val.Value) -> val.Value {
    match val.as_float(v) {
      Some(f) => val.VFloat(math.sqrt(f))
      None    => v
    }
  }
  let result = dist.par_apply_col(df, "a", sqrt_fn)
  inspect.to_markdown(result, 10)
}

// Apply a transform to every column in parallel
fn demo_par_apply_all() -> Str {
  let df         = make_large_df()
  let double_fn  = fn(v :: val.Value) -> val.Value {
    match v {
      val.VInt(n)   => val.VInt(n * 2)
      val.VFloat(f) => val.VFloat(f * 2.0)
      other         => other
    }
  }
  let result = dist.par_apply_all_cols(df, double_fn)
  inspect.to_markdown(result, 10)
}

// Filter rows in parallel (useful for large DataFrames)
fn demo_par_filter() -> Str {
  let df   = make_large_df()
  let pred = fn(row) -> Bool {
    match list.find(row, fn(pair) -> Bool {
      match pair { (k, _) => k == "b" }
    }) {
      Some((_, val.VInt(n))) => n > 30
      _ => false
    }
  }
  let result = dist.par_filter_rows(df, pred)
  inspect.to_markdown(result, 10)
}

// Estimate whether parallelism is worthwhile before committing
fn demo_cost_estimate() -> Str {
  let df   = make_large_df()
  let cost = dist.estimate_par_cost(df)
  str.concat("Estimated parallel cost score: ", int.to_str(cost))
}
