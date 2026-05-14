import "std.list" as list

import "std.map" as map

import "std.str" as str

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

type GroupEntry = { key_str :: Str, key_val :: val.Value, subframe :: frame.DataFrame }

type GroupedFrame = { group_col :: Str, groups :: List[GroupEntry] }

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
        let sub := frame.pick_rows(df, list.reverse(indices))
        list.cons({ key_str: k, key_val: val.parse_str(k), subframe: sub }, acc)
      }))
      Ok({ group_col: col_name, groups: groups })
    },
  }
}

fn agg(gf :: GroupedFrame, specs :: List[AggSpec]) -> frame.DataFrame {
  let key_vals := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
    g.key_val
  })
  let agg_cols := list.map(specs, fn (spec :: AggSpec) -> (Str, List[val.Value]) {
    let vals := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
      apply_agg_op(g.subframe, spec.in_col, spec.op)
    })
    (spec.out_col, vals)
  })
  let all_cols := list.cons((gf.group_col, key_vals), agg_cols)
  match frame.from_columns(all_cols) {
    Ok(df) => frame.record_op(df, prov.op_group_by([gf.group_col])),
    Err(_) => frame.empty(),
  }
}

fn apply_agg_op(sub :: frame.DataFrame, col_name :: Str, op :: AggOp) -> val.Value {
  match op {
    AggSum => match agg.sum_col(sub, col_name) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggMean => match agg.mean_col(sub, col_name) {
      Some(f) => val.vfloat(f),
      None => val.vnull(),
    },
    AggMin => match agg.min_col(sub, col_name) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggMax => match agg.max_col(sub, col_name) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggCount => val.vint(agg.count_all(sub, col_name)),
    AggCountNonNull => val.vint(agg.count_non_null(sub, col_name)),
    AggStd => match agg.std_col(sub, col_name) {
      Some(f) => val.vfloat(f),
      None => val.vnull(),
    },
    AggVar => match agg.variance_col(sub, col_name) {
      Some(f) => val.vfloat(f),
      None => val.vnull(),
    },
    AggNDistinct => val.vint(agg.n_distinct(sub, col_name)),
  }
}

fn value_counts(df :: frame.DataFrame, col_name :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  match group_by(df, col_name) {
    Err(e) => Err(e),
    Ok(gf) => Ok(agg(gf, [agg_spec("count", col_name, AggCount)])),
  }
}

