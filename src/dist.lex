import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.int" as int

import "./value" as val

import "./col" as col

import "./frame" as frame

import "./provenance" as prov

fn estimate_par_cost(df :: frame.DataFrame) -> Int {
  df.nrows * list.len(df.col_names)
}

fn par_apply_col(df :: frame.DataFrame, col_name :: Str, transform :: (val.Value) -> val.Value) -> Result[frame.DataFrame, frame.FrameError] {
  match map.get(df.columns, col_name) {
    None => Err(frame.not_found_error(col_name)),
    Some(c) => {
      let vals := col.col_to_values(c)
      let new_vals := list.map(vals, transform)
      let new_c := col.col_from_values(new_vals)
      let new_cols := map.set(df.columns, col_name, new_c)
      let new_df := { col_names: df.col_names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
      Ok(frame.record_op(new_df, prov.op_add_column(col_name)))
    },
  }
}

fn par_apply_all_cols(df :: frame.DataFrame, transform :: (Str, List[val.Value]) -> List[val.Value]) -> frame.DataFrame {
  let name_col_pairs := list.map(df.col_names, fn (name :: Str) -> (Str, List[val.Value]) {
    match map.get(df.columns, name) {
      None => (name, []),
      Some(c) => (name, col.col_to_values(c)),
    }
  })
  let transformed := list.map(name_col_pairs, fn (p :: (Str, List[val.Value])) -> (Str, List[val.Value]) {
    let name := match p {
      (a, _) => a,
    }
    let xs := match p {
      (_, b) => b,
    }
    (name, transform(name, xs))
  })
  let new_cols := list.fold(transformed, map.new(), fn (m :: Map[Str, col.Col], p :: (Str, List[val.Value])) -> Map[Str, col.Col] {
    let k := match p {
      (a, _) => a,
    }
    let v := match p {
      (_, b) => b,
    }
    map.set(m, k, col.col_from_values(v))
  })
  let new_df := { col_names: df.col_names, columns: new_cols, nrows: df.nrows, provenance: df.provenance }
  frame.record_op(new_df, prov.op_pipe("par_apply_all_cols"))
}

fn par_filter_rows(df :: frame.DataFrame, pred_desc :: Str, pred :: (List[(Str, val.Value)]) -> Bool) -> frame.DataFrame {
  let all_rows := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> (Int, Bool) {
    (i, pred(frame.get_row(df, i)))
  })
  let kept_indices := list.map(list.filter(all_rows, fn (p :: (Int, Bool)) -> Bool {
    match p {
      (_, b) => b,
    }
  }), fn (p :: (Int, Bool)) -> Int {
    match p {
      (i, _) => i,
    }
  })
  let sub := frame.pick_rows(df, kept_indices)
  frame.record_op(sub, prov.op_filter(pred_desc, list.len(kept_indices)))
}

fn par_map_rows(df :: frame.DataFrame, transform :: (List[(Str, val.Value)]) -> List[(Str, val.Value)]) -> Result[frame.DataFrame, frame.FrameError] {
  let rows := list.map(frame.range_list(0, df.nrows), fn (i :: Int) -> List[(Str, val.Value)] {
    frame.get_row(df, i)
  })
  let new_rows := list.map(rows, transform)
  let cols := list.map(df.col_names, fn (name :: Str) -> (Str, List[val.Value]) {
    let col_vals := list.map(new_rows, fn (row :: List[(Str, val.Value)]) -> val.Value {
      list.fold(row, val.vnull(), fn (acc :: val.Value, p :: (Str, val.Value)) -> val.Value {
        let k := match p {
          (a, _) => a,
        }
        let v := match p {
          (_, b) => b,
        }
        if val.is_null(acc) {
          if k == name {
            v
          } else {
            val.vnull()
          }
        } else {
          acc
        }
      })
    })
    (name, col_vals)
  })
  match frame.from_columns(cols) {
    Err(e) => Err(e),
    Ok(df2) => Ok(frame.record_op(df2, prov.op_pipe("par_map_rows"))),
  }
}

