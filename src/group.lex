import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.int" as int

import "./value" as val

import "./col" as col

import "./frame" as frame

import "./agg" as agg

import "./provenance" as prov

type AggOp = AggSum | AggMean | AggMin | AggMax | AggCount | AggCountNonNull | AggStd | AggVar | AggNDistinct

type AggSpec = { out_col :: Str, in_col :: Str, op :: AggOp }

fn agg_sum() -> AggOp {
  AggSum
}

fn agg_mean() -> AggOp {
  AggMean
}

fn agg_min() -> AggOp {
  AggMin
}

fn agg_max() -> AggOp {
  AggMax
}

fn agg_count() -> AggOp {
  AggCount
}

fn agg_count_non_null() -> AggOp {
  AggCountNonNull
}

fn agg_std() -> AggOp {
  AggStd
}

fn agg_var() -> AggOp {
  AggVar
}

fn agg_n_distinct() -> AggOp {
  AggNDistinct
}

fn agg_spec(out_col :: Str, in_col :: Str, op :: AggOp) -> AggSpec {
  { out_col: out_col, in_col: in_col, op: op }
}

type GroupEntry = { key_str :: Str, key_val :: val.Value, indices :: List[Int] }

type GroupedFrame = { source_df :: frame.DataFrame, group_col :: Str, groups :: List[GroupEntry] }

fn group_by(df :: frame.DataFrame, col_name :: Str) -> Result[GroupedFrame, frame.FrameError] {
  match map.get(df.columns, col_name) {
    None => Err(frame.not_found_error(col_name)),
    Some(c) => {
      let key_vals := col.col_to_values(c)
      let idx_map := list.fold(list.enumerate(key_vals), map.new(), fn (m :: Map[Str, List[Int]], p :: (Int, val.Value)) -> Map[Str, List[Int]] {
        let i := match p {
          (a, _) => a,
        }
        let v := match p {
          (_, b) => b,
        }
        let k := val.to_str(v)
        let existing := match map.get(m, k) {
          Some(xs) => xs,
          None => [],
        }
        map.set(m, k, list.cons(i, existing))
      })
      let groups := list.reverse(list.fold(map.entries(idx_map), [], fn (acc :: List[GroupEntry], pair :: (Str, List[Int])) -> List[GroupEntry] {
        let k := match pair {
          (a, _) => a,
        }
        let indices := match pair {
          (_, b) => b,
        }
        list.cons({ key_str: k, key_val: val.parse_str(k), indices: list.reverse(indices) }, acc)
      }))
      Ok({ source_df: df, group_col: col_name, groups: groups })
    },
  }
}

fn build_col_index(df :: frame.DataFrame, col_name :: Str) -> Map[Str, val.Value] {
  match map.get(df.columns, col_name) {
    None => map.new(),
    Some(c) => {
      let vs := col.col_to_values(c)
      list.fold(list.enumerate(vs), map.new(), fn (m :: Map[Str, val.Value], p :: (Int, val.Value)) -> Map[Str, val.Value] {
        let i := match p {
          (a, _) => a,
        }
        let v := match p {
          (_, b) => b,
        }
        map.set(m, int.to_str(i), v)
      })
    },
  }
}

fn apply_agg_indexed(col_idx :: Map[Str, val.Value], indices :: List[Int], op :: AggOp) -> val.Value {
  match op {
    AggCount => val.vint(list.len(indices)),
    _ => {
      let vals := list.map(indices, fn (i :: Int) -> val.Value {
        match map.get(col_idx, int.to_str(i)) {
          Some(v) => v,
          None => val.vnull(),
        }
      })
      let c := col.col_from_values(vals)
      match op {
        AggCount => val.vint(list.len(indices)),
        AggSum => match col.col_sum(c) {
          Some(v) => v,
          None => val.vnull(),
        },
        AggMean => match col.col_mean(c) {
          Some(f) => val.vfloat(f),
          None => val.vnull(),
        },
        AggMin => match col.col_min(c) {
          Some(v) => v,
          None => val.vnull(),
        },
        AggMax => match col.col_max(c) {
          Some(v) => v,
          None => val.vnull(),
        },
        AggCountNonNull => val.vint(col.col_len(c) - col.col_null_count(c)),
        AggStd => match col.col_std(c) {
          Some(f) => val.vfloat(f),
          None => val.vnull(),
        },
        AggVar => match col.col_variance(c) {
          Some(f) => val.vfloat(f),
          None => val.vnull(),
        },
        AggNDistinct => val.vint(col.col_n_distinct(c)),
      }
    },
  }
}

fn agg(gf :: GroupedFrame, specs :: List[AggSpec]) -> frame.DataFrame {
  let key_vals := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
    g.key_val
  })
  let agg_cols := list.map(specs, fn (spec :: AggSpec) -> (Str, List[val.Value]) {
    let col_idx := build_col_index(gf.source_df, spec.in_col)
    let vals := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
      apply_agg_indexed(col_idx, g.indices, spec.op)
    })
    (spec.out_col, vals)
  })
  let all_cols := list.cons((gf.group_col, key_vals), agg_cols)
  match frame.from_columns(all_cols) {
    Ok(df) => frame.record_op(df, prov.op_group_by([gf.group_col])),
    Err(_) => frame.empty(),
  }
}

fn value_counts(df :: frame.DataFrame, col_name :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  match group_by(df, col_name) {
    Err(e) => Err(e),
    Ok(gf) => Ok(agg(gf, [agg_spec("count", col_name, AggCount)])),
  }
}

