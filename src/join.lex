import "std.list" as list

import "std.map" as map

import "std.str" as str

import "./value" as val

import "./col" as col

import "./frame" as frame

import "./provenance" as prov

fn inner_join(left :: frame.DataFrame, right :: frame.DataFrame, on :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  match (map.get(left.columns, on), map.get(right.columns, on)) {
    (None, _) => Err(frame.not_found_error(str.concat("left.", on))),
    (_, None) => Err(frame.not_found_error(str.concat("right.", on))),
    (Some(_), Some(_)) => {
      let right_index := build_index(right, on)
      let out_names := result_col_names(left, right, on)
      let empty_acc := init_acc(out_names)
      let filled := list.fold(frame.range_list(0, left.nrows), empty_acc, fn (acc :: Map[Str, List[val.Value]], li :: Int) -> Map[Str, List[val.Value]] {
        let lk := col_nth_df(left, on, li)
        let matches := match map.get(right_index, val.to_str(lk)) {
          Some(is) => is,
          None => [],
        }
        list.fold(matches, acc, fn (acc2 :: Map[Str, List[val.Value]], ri :: Int) -> Map[Str, List[val.Value]] {
          append_pair(acc2, out_names, left, right, on, li, ri)
        })
      })
      finish(filled, out_names, "inner", on)
    },
  }
}

fn left_join(left :: frame.DataFrame, right :: frame.DataFrame, on :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  match (map.get(left.columns, on), map.get(right.columns, on)) {
    (None, _) => Err(frame.not_found_error(str.concat("left.", on))),
    (_, None) => Err(frame.not_found_error(str.concat("right.", on))),
    (Some(_), Some(_)) => {
      let right_index := build_index(right, on)
      let out_names := result_col_names(left, right, on)
      let empty_acc := init_acc(out_names)
      let filled := list.fold(frame.range_list(0, left.nrows), empty_acc, fn (acc :: Map[Str, List[val.Value]], li :: Int) -> Map[Str, List[val.Value]] {
        let lk := col_nth_df(left, on, li)
        let matches := match map.get(right_index, val.to_str(lk)) {
          Some(is) => is,
          None => [],
        }
        if list.is_empty(matches) {
          append_null_right(acc, out_names, left, right, on, li)
        } else {
          list.fold(matches, acc, fn (acc2 :: Map[Str, List[val.Value]], ri :: Int) -> Map[Str, List[val.Value]] {
            append_pair(acc2, out_names, left, right, on, li, ri)
          })
        }
      })
      finish(filled, out_names, "left", on)
    },
  }
}

fn cross_join(left :: frame.DataFrame, right :: frame.DataFrame) -> Result[frame.DataFrame, frame.FrameError] {
  let right_names := list.map(right.col_names, fn (n :: Str) -> Str {
    if list.fold(left.col_names, false, fn (acc :: Bool, ln :: Str) -> Bool {
      acc or ln == n
    }) {
      str.concat(n, "_right")
    } else {
      n
    }
  })
  let all_names := list.concat(left.col_names, right_names)
  let empty_acc := init_acc(all_names)
  let filled := list.fold(frame.range_list(0, left.nrows), empty_acc, fn (acc :: Map[Str, List[val.Value]], li :: Int) -> Map[Str, List[val.Value]] {
    list.fold(frame.range_list(0, right.nrows), acc, fn (acc2 :: Map[Str, List[val.Value]], ri :: Int) -> Map[Str, List[val.Value]] {
      let left_vals := list.map(left.col_names, fn (n :: Str) -> val.Value {
        col_nth_df(left, n, li)
      })
      let right_vals := list.map(right.col_names, fn (n :: Str) -> val.Value {
        col_nth_df(right, n, ri)
      })
      let row := list.concat(zip_names(left.col_names, left_vals), zip_names(right_names, right_vals))
      push_row(acc2, row)
    })
  })
  finish(filled, all_names, "cross", "cross")
}

fn col_nth_df(df :: frame.DataFrame, name :: Str, i :: Int) -> val.Value {
  match map.get(df.columns, name) {
    None => val.vnull(),
    Some(c) => col.col_nth(c, i),
  }
}

fn zip_names(names :: List[Str], vals :: List[val.Value]) -> List[(Str, val.Value)] {
  list.reverse(list.fold(list.enumerate(names), [], fn (acc :: List[(Str, val.Value)], p :: (Int, Str)) -> List[(Str, val.Value)] {
    let i := match p {
      (a, _) => a,
    }
    let name := match p {
      (_, b) => b,
    }
    let v := nth_val(vals, i)
    list.cons((name, v), acc)
  }))
}

fn nth_val(xs :: List[val.Value], i :: Int) -> val.Value {
  let m := list.fold(list.enumerate(xs), map.new(), fn (acc :: Map[Str, val.Value], p :: (Int, val.Value)) -> Map[Str, val.Value] {
    let idx := match p {
      (a, _) => a,
    }
    let v := match p {
      (_, b) => b,
    }
    map.set(acc, int.to_str(idx), v)
  })
  match map.get(m, int.to_str(i)) {
    Some(v) => v,
    None => val.vnull(),
  }
}

fn build_index(df :: frame.DataFrame, name :: Str) -> Map[Str, List[Int]] {
  match map.get(df.columns, name) {
    None => map.new(),
    Some(c) => {
      let vals := col.col_to_values(c)
      list.fold(list.enumerate(vals), map.new(), fn (m :: Map[Str, List[Int]], p :: (Int, val.Value)) -> Map[Str, List[Int]] {
        let i := match p {
          (a, _) => a,
        }
        let v := match p {
          (_, b) => b,
        }
        let k := val.to_str(v)
        let xs := match map.get(m, k) {
          Some(js) => js,
          None => [],
        }
        map.set(m, k, list.cons(i, xs))
      })
    },
  }
}

fn result_col_names(left :: frame.DataFrame, right :: frame.DataFrame, on :: Str) -> List[Str] {
  let left_rest := list.filter(left.col_names, fn (n :: Str) -> Bool {
    n != on
  })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool {
    n != on
  })
  let right_dis := list.map(right_rest, fn (n :: Str) -> Str {
    if list.fold(left_rest, false, fn (acc :: Bool, ln :: Str) -> Bool {
      acc or ln == n
    }) {
      str.concat(n, "_right")
    } else {
      n
    }
  })
  list.concat(list.cons(on, left_rest), right_dis)
}

fn init_acc(names :: List[Str]) -> Map[Str, List[val.Value]] {
  list.fold(names, map.new(), fn (m :: Map[Str, List[val.Value]], n :: Str) -> Map[Str, List[val.Value]] {
    map.set(m, n, [])
  })
}

fn push_row(m :: Map[Str, List[val.Value]], row :: List[(Str, val.Value)]) -> Map[Str, List[val.Value]] {
  list.fold(row, m, fn (acc :: Map[Str, List[val.Value]], pair :: (Str, val.Value)) -> Map[Str, List[val.Value]] {
    let name := match pair {
      (k, _) => k,
    }
    let v := match pair {
      (_, x) => x,
    }
    let existing := match map.get(acc, name) {
      Some(xs) => xs,
      None => [],
    }
    map.set(acc, name, list.cons(v, existing))
  })
}

fn append_pair(acc :: Map[Str, List[val.Value]], names :: List[Str], left :: frame.DataFrame, right :: frame.DataFrame, on :: Str, li :: Int, ri :: Int) -> Map[Str, List[val.Value]] {
  let left_rest := list.filter(left.col_names, fn (n :: Str) -> Bool {
    n != on
  })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool {
    n != on
  })
  let on_val := col_nth_df(left, on, li)
  let left_vals := list.map(left_rest, fn (n :: Str) -> val.Value {
    col_nth_df(left, n, li)
  })
  let right_vals := list.map(right_rest, fn (n :: Str) -> val.Value {
    col_nth_df(right, n, ri)
  })
  let row := list.concat(list.cons((on, on_val), zip_names(left_rest, left_vals)), zip_names(disambig_right(left_rest, right_rest), right_vals))
  push_row(acc, row)
}

fn append_null_right(acc :: Map[Str, List[val.Value]], names :: List[Str], left :: frame.DataFrame, right :: frame.DataFrame, on :: Str, li :: Int) -> Map[Str, List[val.Value]] {
  let left_rest := list.filter(left.col_names, fn (n :: Str) -> Bool {
    n != on
  })
  let right_rest := list.filter(right.col_names, fn (n :: Str) -> Bool {
    n != on
  })
  let on_val := col_nth_df(left, on, li)
  let left_vals := list.map(left_rest, fn (n :: Str) -> val.Value {
    col_nth_df(left, n, li)
  })
  let null_pairs := list.map(disambig_right(left_rest, right_rest), fn (n :: Str) -> (Str, val.Value) {
    (n, val.vnull())
  })
  let row := list.concat(list.cons((on, on_val), zip_names(left_rest, left_vals)), null_pairs)
  push_row(acc, row)
}

fn disambig_right(left_rest :: List[Str], right_rest :: List[Str]) -> List[Str] {
  list.map(right_rest, fn (n :: Str) -> Str {
    if list.fold(left_rest, false, fn (acc :: Bool, ln :: Str) -> Bool {
      acc or ln == n
    }) {
      str.concat(n, "_right")
    } else {
      n
    }
  })
}

fn finalize_cols(names :: List[Str], acc :: Map[Str, List[val.Value]]) -> List[(Str, List[val.Value])] {
  list.map(names, fn (name :: Str) -> (Str, List[val.Value]) {
    let col_rev := match map.get(acc, name) {
      Some(xs) => xs,
      None => [],
    }
    (name, list.reverse(col_rev))
  })
}

fn finish(acc :: Map[Str, List[val.Value]], names :: List[Str], kind :: Str, on :: Str) -> Result[frame.DataFrame, frame.FrameError] {
  let final_cols := finalize_cols(names, acc)
  match frame.from_columns(final_cols) {
    Err(e) => Err(e),
    Ok(df) => Ok(frame.record_op(df, prov.op_join(kind, on))),
  }
}

