import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.int" as int

import "./value" as val

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

fn group_by(df :: frame.DataFrame, col :: Str) -> Result[GroupedFrame, frame.FrameError] {
  match map.get(df.columns, col) {
    None => Err(frame.not_found_error(col)),
    Some(key_col) => {
      let idx_map := list.fold(list.enumerate(key_col), map.new(), fn (m :: Map[Str, List[Int]], p :: (Int, val.Value)) -> Map[Str, List[Int]] {
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
      let groups_rev := list.fold(map.entries(idx_map), [], fn (acc :: List[GroupEntry], pair :: (Str, List[Int])) -> List[GroupEntry] {
        let k := match pair {
          (a, _) => a,
        }
        let indices := match pair {
          (_, b) => b,
        }
        let sub := frame.pick_rows(df, list.reverse(indices))
        let entry := { key_str: k, key_val: val.parse_str(k), subframe: sub }
        list.cons(entry, acc)
      })
      let groups := list.reverse(groups_rev)
      Ok({ group_col: col, groups: groups })
    },
  }
}

fn agg(gf :: GroupedFrame, specs :: List[AggSpec]) -> frame.DataFrame {
  let n := list.len(gf.groups)
  let key_col := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
    g.key_val
  })
  let agg_cols := list.map(specs, fn (spec :: AggSpec) -> (Str, List[val.Value]) {
    let values := list.map(gf.groups, fn (g :: GroupEntry) -> val.Value {
      apply_agg_op(g.subframe, spec.in_col, spec.op)
    })
    (spec.out_col, values)
  })
  let all_cols := list.cons((gf.group_col, key_col), agg_cols)
  match frame.from_columns(all_cols) {
    Ok(df) => frame.record_op(df, prov.op_group_by([gf.group_col])),
    Err(_) => frame.empty(),
  }
}

fn apply_agg_op(sub :: frame.DataFrame, col :: Str, op :: AggOp) -> val.Value {
  match op {
    AggSum => match agg.sum_col(sub, col) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggMean => match agg.mean_col(sub, col) {
      Some(x) => val.vfloat(x),
      None => val.vnull(),
    },
    AggMin => match agg.min_col(sub, col) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggMax => match agg.max_col(sub, col) {
      Some(v) => v,
      None => val.vnull(),
    },
    AggCount => val.vint(agg.count_all(sub, col)),
    AggCountNonNull => val.vint(agg.count_non_null(sub, col)),
    AggStd => match agg.std_col(sub, col) {
      Some(x) => val.vfloat(x),
      None => val.vnull(),
    },
    AggVar => match agg.variance_col(sub, col) {
      Some(x) => val.vfloat(x),
      None => val.vnull(),
    },
    AggNDistinct => val.vint(agg.n_distinct(sub, col)),
  }
}

fn value_counts(df :: frame.DataFrame, col :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  match group_by(df, col) {
    Err(e) => Err(e),
    Ok(gf) => Ok(agg(gf, [agg_spec("count", col, AggCount)])),
  }
}

