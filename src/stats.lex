# lex-frame — statistical summary functions
#
# describe: per-column summary statistics (count, mean, std, min, max).
# correlation: Pearson r between two numeric columns.
# null_counts: count nulls per column (used by inspect.lex).

import "std.list"  as list
import "std.map"   as map
import "std.str"   as str
import "std.int"   as int
import "std.float" as float
import "std.math"  as math
import "./value"  as val
import "./frame"  as frame
import "./agg"    as agg

# Returns a summary DataFrame with columns:
# stat | col1 | col2 | ... (one column per numeric column in df)
# Rows: count, mean, std, min, max
fn describe(df :: frame.DataFrame) -> frame.DataFrame {
  let numeric_cols := list.filter(df.col_names, fn (name :: Str) -> Bool {
    match map.get(df.columns, name) {
      None     => false,
      Some(xs) => list.any(xs, fn (v :: Value) -> Bool { val.is_numeric(v) }),
    }
  })
  let stat_names := ["count", "mean", "std", "min", "max"]
  let stat_col   := list.map(stat_names, fn (s :: Str) -> Value { val.VStr(s) })
  let data_cols  := list.map(numeric_cols, fn (name :: Str) -> (Str, List[Value]) {
    match map.get(df.columns, name) {
      None     => (name, [val.VNull, val.VNull, val.VNull, val.VNull, val.VNull]),
      Some(xs) => {
        let cnt  := val.VInt(agg.count_non_null(xs))
        let mean := match agg.mean_col(xs)     { Some(x) => val.VFloat(x), None => val.VNull }
        let std  := match agg.std_col(xs)      { Some(x) => val.VFloat(x), None => val.VNull }
        let mn   := match agg.min_col(xs)      { Some(v) => v,             None => val.VNull }
        let mx   := match agg.max_col(xs)      { Some(v) => v,             None => val.VNull }
        (name, [cnt, mean, std, mn, mx])
      },
    }
  })
  let all_cols := list.concat([("stat", stat_col)], data_cols)
  match frame.from_columns(all_cols) {
    Ok(d)  => d,
    Err(_) => frame.empty(),
  }
}

# Pearson correlation between two numeric columns.
# Returns Err if either column is not found or has no numeric data.
fn correlation(
  df   :: frame.DataFrame,
  col1 :: Str,
  col2 :: Str
) -> Result[Float, frame.FrameError] {
  match (map.get(df.columns, col1), map.get(df.columns, col2)) {
    (None, _) => Err(frame.not_found_error(col1)),
    (_, None) => Err(frame.not_found_error(col2)),
    (Some(xs), Some(ys)) => {
      let pairs := list.filter(
        list.map(list.zip(xs, ys), fn (p :: (Value, Value)) -> (Float, Float) {
          let a := match p { (a2, _) => a2 }
          let b := match p { (_, b2) => b2 }
          (match val.as_float(a) { Some(x) => x, None => 0.0 },
           match val.as_float(b) { Some(x) => x, None => 0.0 })
        }),
        fn (_p :: (Float, Float)) -> Bool { true }
      )
      let n := int.to_float(list.len(pairs))
      if n == 0.0 {
        Err(frame.frame_error("no_numeric_data", "no numeric pairs found", str.concat(col1, str.concat(", ", col2))))
      } else {
        let sx  := list.fold(pairs, 0.0, fn (a :: Float, p :: (Float, Float)) -> Float { a + match p { (x, _) => x } })
        let sy  := list.fold(pairs, 0.0, fn (a :: Float, p :: (Float, Float)) -> Float { a + match p { (_, y) => y } })
        let sxy := list.fold(pairs, 0.0, fn (a :: Float, p :: (Float, Float)) -> Float {
          let x := match p { (xv, _) => xv }
          let y := match p { (_, yv) => yv }
          a + x * y
        })
        let sx2 := list.fold(pairs, 0.0, fn (a :: Float, p :: (Float, Float)) -> Float { let x := match p { (xv, _) => xv }
          a + x * x })
        let sy2 := list.fold(pairs, 0.0, fn (a :: Float, p :: (Float, Float)) -> Float { let y := match p { (_, yv) => yv }
          a + y * y })
        let num := n * sxy - sx * sy
        let den := math.sqrt((n * sx2 - sx * sx) * (n * sy2 - sy * sy))
        if den == 0.0 {
          Err(frame.frame_error("zero_variance", "one or both columns have zero variance", ""))
        } else {
          Ok(num / den)
        }
      }
    },
  }
}

# Count null values per column. Returns 2-col DataFrame: column | null_count
fn null_counts(df :: frame.DataFrame) -> frame.DataFrame {
  let col_vals   := list.map(df.col_names, fn (n :: Str) -> Value { val.VStr(n) })
  let count_vals := list.map(df.col_names, fn (n :: Str) -> Value {
    match map.get(df.columns, n) {
      None     => val.VNull,
      Some(xs) => val.VInt(list.len(list.filter(xs, fn (v :: Value) -> Bool { val.is_null(v) }))),
    }
  })
  match frame.from_columns([("column", col_vals), ("null_count", count_vals)]) {
    Ok(d)  => d,
    Err(_) => frame.empty(),
  }
}
