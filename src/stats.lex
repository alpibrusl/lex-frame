# lex-frame — statistical summary functions
#
# describe: per-column summary statistics (count, mean, std, min, max).
# correlation: Pearson r between two numeric columns.
# null_counts: count nulls per column.

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
      Some(xs) => list.any(xs, fn (v :: val.Value) -> Bool { val.is_numeric(v) }),
    }
  })
  let stat_names := ["count", "mean", "std", "min", "max"]
  let stat_col   := list.map(stat_names, fn (s :: Str) -> val.Value { val.VStr(s) })
  let data_cols  := list.map(numeric_cols, fn (name :: Str) -> (Str, List[val.Value]) {
    match map.get(df.columns, name) {
      None     => (name, [val.VNull, val.VNull, val.VNull, val.VNull, val.VNull]),
      Some(xs) => {
        let tmp  := match frame.from_columns([(name, xs)]) { Ok(d) => d, Err(_) => frame.empty() }
        let cnt  := val.VInt(agg.count_non_null(tmp, name))
        let mean := match agg.mean_col(tmp, name) { Some(x) => val.VFloat(x), None => val.VNull }
        let std  := match agg.std_col(tmp, name)  { Some(x) => val.VFloat(x), None => val.VNull }
        let mn   := match agg.min_col(tmp, name)  { Some(v) => v,             None => val.VNull }
        let mx   := match agg.max_col(tmp, name)  { Some(v) => v,             None => val.VNull }
        (name, [cnt, mean, std, mn, mx])
      },
    }
  })
  let all_cols := list.cons(("stat", stat_col), data_cols)
  match frame.from_columns(all_cols) {
    Ok(d)  => d,
    Err(_) => frame.empty(),
  }
}

# Pearson correlation between two numeric columns.
# Returns None if either column is missing or has no numeric pairs.
fn correlation(
  df   :: frame.DataFrame,
  col1 :: Str,
  col2 :: Str
) -> Option[Float] {
  match (map.get(df.columns, col1), map.get(df.columns, col2)) {
    (None, _) => None,
    (_, None) => None,
    (Some(xs), Some(ys)) => {
      let en := list.enumerate(xs)
      # Keep only pairs where both values are numeric.
      let numeric_en := list.filter(en, fn (p :: (Int, val.Value)) -> Bool {
        let i  := match p { (a, _) => a }
        let xv := match p { (_, b) => b }
        match val.as_float(xv) {
          None    => false,
          Some(_) => match val.as_float(frame.nth_value(ys, i)) {
            None    => false,
            Some(_) => true,
          },
        }
      })
      let cnt := list.len(numeric_en)
      if cnt == 0 { None }
      else {
        let n   := int.to_float(cnt)
        let sx  := list.fold(numeric_en, 0.0, fn (a :: Float, p :: (Int, val.Value)) -> Float {
          let xv := match p { (_, b) => b }
          match val.as_float(xv) { Some(x) => a + x, None => a }
        })
        let sy  := list.fold(numeric_en, 0.0, fn (a :: Float, p :: (Int, val.Value)) -> Float {
          let i := match p { (idx, _) => idx }
          match val.as_float(frame.nth_value(ys, i)) { Some(y) => a + y, None => a }
        })
        let sxy := list.fold(numeric_en, 0.0, fn (a :: Float, p :: (Int, val.Value)) -> Float {
          let i  := match p { (idx, _) => idx }
          let xv := match p { (_, b) => b }
          let x  := match val.as_float(xv) { Some(v) => v, None => 0.0 }
          let y  := match val.as_float(frame.nth_value(ys, i)) { Some(v) => v, None => 0.0 }
          a + x * y
        })
        let sx2 := list.fold(numeric_en, 0.0, fn (a :: Float, p :: (Int, val.Value)) -> Float {
          let xv := match p { (_, b) => b }
          let x  := match val.as_float(xv) { Some(v) => v, None => 0.0 }
          a + x * x
        })
        let sy2 := list.fold(numeric_en, 0.0, fn (a :: Float, p :: (Int, val.Value)) -> Float {
          let i := match p { (idx, _) => idx }
          let y := match val.as_float(frame.nth_value(ys, i)) { Some(v) => v, None => 0.0 }
          a + y * y
        })
        let num := n * sxy - sx * sy
        let den := math.sqrt((n * sx2 - sx * sx) * (n * sy2 - sy * sy))
        if den == 0.0 { Some(1.0) }
        else { Some(num / den) }
      }
    },
  }
}

# Count null values per column.
# Returns a 3-column DataFrame: column | null_count | null_pct
fn null_counts(df :: frame.DataFrame) -> frame.DataFrame {
  let n          := df.nrows
  let col_vals   := list.map(df.col_names, fn (nm :: Str) -> val.Value { val.VStr(nm) })
  let count_vals := list.map(df.col_names, fn (nm :: Str) -> val.Value {
    match map.get(df.columns, nm) {
      None     => val.VNull,
      Some(xs) => val.VInt(list.len(list.filter(xs, fn (v :: val.Value) -> Bool { val.is_null(v) }))),
    }
  })
  let pct_vals := list.map(count_vals, fn (v :: val.Value) -> val.Value {
    match val.as_int(v) {
      None    => val.VNull,
      Some(c) => if n == 0 { val.VFloat(0.0) }
                 else { val.VFloat(int.to_float(c) / int.to_float(n) * 100.0) },
    }
  })
  match frame.from_columns([("column", col_vals), ("null_count", count_vals), ("null_pct", pct_vals)]) {
    Ok(d)  => d,
    Err(_) => frame.empty(),
  }
}
