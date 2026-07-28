import "std.list" as list

import "std.str" as str

import "std.map" as map

import "std.arrow" as arrow

import "./value" as val

import "./col" as col

import "./provenance" as prov

# `arrow_table` is an optional arrow.Table backing — set when the
# DataFrame was built via `from_arrow_table` / `io.read_csv_fast` /
# `io.read_parquet`, or produced by one of the `_fast` ops. When
# present, the fast-path ops (`agg.sum_col_fast`, `select.filter_*_fast`,
# `sort.sort_by_fast`, `group.group_agg_fast`, `join.*_join_fast`)
# dispatch through std.arrow / std.df kernels for a 50-1000x speedup
# over the List[Value]-based path. When None, the `_fast` ops fall
# back to the legacy Map[Str, Col] representation.
#
# The two representations are NOT kept in sync: an arrow-backed
# DataFrame has an EMPTY `columns` map (there is no arrow -> List
# materializer in std.arrow yet), so legacy ops that walk
# `df.columns` (filter_rows with a closure, the inspect walkers,
# dist.par_*) see no data on an arrow-backed frame. Stay on the
# `_fast` ops end-to-end for arrow-backed frames, and use
# `arrow.write_csv` / `io.write_csv_fast` to get data out.
type DataFrame = { col_names :: List[Str], columns :: Map[Str, col.Col], nrows :: Int, provenance :: List[prov.Op], arrow_table :: Option[Table] }

type FrameError = { code :: Str, message :: Str, context :: Str }

fn frame_err(code :: Str, message :: Str, context :: Str) -> FrameError {
  { code: code, message: message, context: context }
}

fn not_found_error(name :: Str) -> FrameError {
  frame_err("FRAME_COLUMN_NOT_FOUND", str.concat("column '", str.concat(name, "' not found")), name)
}

# Standard refusal for ops that only run on the legacy (list-backed)
# engine. An arrow-backed frame's legacy `columns` map is empty, so
# instead of silently returning empty results (the pre-#19 behavior)
# these ops error with the fast-path alternative in the message.
fn legacy_only_error(op :: Str, hint :: Str) -> FrameError {
  frame_err("FRAME_LEGACY_ONLY", str.concat(op, str.concat(" runs on the legacy engine and this frame is arrow-backed (empty legacy columns); ", hint)), op)
}

fn record_op(df :: DataFrame, op :: prov.Op) -> DataFrame {
  { col_names: df.col_names, columns: df.columns, nrows: df.nrows, provenance: list.cons(op, df.provenance), arrow_table: df.arrow_table }
}

fn empty() -> DataFrame {
  { col_names: [], columns: map.new(), nrows: 0, provenance: [], arrow_table: None }
}

# Construct a DataFrame backed by an arrow.Table. The `columns` map is
# left empty — this DataFrame is intended for the fast-path agg ops
# (agg.sum_col_fast / mean_col_fast / etc.) and io.read_csv_fast, which
# read from `arrow_table` directly via arrow kernels for a 50-1000x
# speedup over the List[Value] path.
#
# **Sharp edge for this slice:** legacy ops that walk `df.columns`
# (select.filter_rows with a closure, dist.par_filter_rows, the inspect
# walkers) will see an empty column map on arrow-backed DataFrames
# and silently produce empty results. Convert to the legacy
# representation first via `frame.materialize(df)` if you need the
# row-API. The deeper migration that backs col.Col with arrow
# directly is a follow-up (see lex-frame#6 sub-issue).
fn from_arrow_table(t :: Table) -> DataFrame {
  { col_names: arrow.col_names(t), columns: map.new(), nrows: arrow.nrows(t), provenance: [prov.op_load("<arrow_table>", arrow.nrows(t))], arrow_table: Some(t) }
}

# Wrap an arrow.Table produced by a fast-path op (std.df filter /
# sort / group_by_agg / join) into a DataFrame, carrying forward the
# input frame's provenance and consing the op that produced it. This
# is what keeps `inspect.history` truthful across `_fast` pipelines —
# `from_arrow_table` would reset the trail to a single `load` op.
fn with_arrow_table(df :: DataFrame, t :: Table, op :: prov.Op) -> DataFrame {
  { col_names: arrow.col_names(t), columns: map.new(), nrows: arrow.nrows(t), provenance: list.cons(op, df.provenance), arrow_table: Some(t) }
}

fn from_columns(pairs :: List[(Str, List[val.Value])]) -> Result[DataFrame, FrameError] {
  if list.is_empty(pairs) {
    Ok(empty())
  } else {
    match list.head(pairs) {
      None => Ok(empty()),
      Some(first_pair) => {
        let expected := list.len(match first_pair {
          (_, c) => c,
        })
        let length_ok := list.fold(pairs, true, fn (acc :: Bool, pair :: (Str, List[val.Value])) -> Bool {
          acc and list.len(match pair {
            (_, c) => c,
          }) == expected
        })
        if length_ok {
          let names := list.map(pairs, fn (p :: (Str, List[val.Value])) -> Str {
            match p {
              (n, _) => n,
            }
          })
          let col_map := list.fold(pairs, map.new(), fn (acc :: Map[Str, col.Col], pair :: (Str, List[val.Value])) -> Map[Str, col.Col] {
            let name := match pair {
              (n, _) => n,
            }
            let vals := match pair {
              (_, c) => c,
            }
            map.set(acc, name, col.col_from_values(vals))
          })
          Ok({ col_names: names, columns: col_map, nrows: expected, provenance: [prov.op_load("<from_columns>", expected)], arrow_table: None })
        } else {
          let bad := list.fold(pairs, None, fn (acc :: Option[Str], pair :: (Str, List[val.Value])) -> Option[Str] {
            match acc {
              Some(_) => acc,
              None => {
                let n := match pair {
                  (nm, _) => nm,
                }
                let c := match pair {
                  (_, cv) => cv,
                }
                if list.len(c) != expected {
                  Some(n)
                } else {
                  None
                }
              },
            }
          })
          match bad {
            None => Err(frame_err("FRAME_LENGTH_MISMATCH", "column length mismatch", "")),
            Some(n) => Err(frame_err("FRAME_LENGTH_MISMATCH", str.concat("column '", str.concat(n, "' has wrong length")), n)),
          }
        }
      },
    }
  }
}

fn from_typed_columns(pairs :: List[(Str, col.Col)]) -> Result[DataFrame, FrameError] {
  if list.is_empty(pairs) {
    Ok(empty())
  } else {
    match list.head(pairs) {
      None => Ok(empty()),
      Some(first_pair) => {
        let expected := col.col_len(match first_pair {
          (_, c) => c,
        })
        let length_ok := list.fold(pairs, true, fn (acc :: Bool, pair :: (Str, col.Col)) -> Bool {
          acc and col.col_len(match pair {
            (_, c) => c,
          }) == expected
        })
        if length_ok {
          let names := list.map(pairs, fn (p :: (Str, col.Col)) -> Str {
            match p {
              (n, _) => n,
            }
          })
          let col_map := list.fold(pairs, map.new(), fn (acc :: Map[Str, col.Col], pair :: (Str, col.Col)) -> Map[Str, col.Col] {
            let name := match pair {
              (n, _) => n,
            }
            let c := match pair {
              (_, c) => c,
            }
            map.set(acc, name, c)
          })
          Ok({ col_names: names, columns: col_map, nrows: expected, provenance: [], arrow_table: None })
        } else {
          Err(frame_err("FRAME_LENGTH_MISMATCH", "column length mismatch", ""))
        }
      },
    }
  }
}

fn nth_value(c :: col.Col, idx :: Int) -> val.Value {
  col.col_nth(c, idx)
}

fn pick_rows(df :: DataFrame, indices :: List[Int]) -> DataFrame {
  let new_map := list.fold(df.col_names, map.new(), fn (acc :: Map[Str, col.Col], name :: Str) -> Map[Str, col.Col] {
    match map.get(df.columns, name) {
      None => acc,
      Some(c) => map.set(acc, name, col.col_pick(c, indices)),
    }
  })
  { col_names: df.col_names, columns: new_map, nrows: list.len(indices), provenance: df.provenance, arrow_table: None }
}

fn range_list(start :: Int, stop :: Int) -> List[Int] {
  if start >= stop {
    []
  } else {
    list.cons(start, range_list(start + 1, stop))
  }
}

fn get_row(df :: DataFrame, idx :: Int) -> List[(Str, val.Value)] {
  list.map(df.col_names, fn (name :: Str) -> (Str, val.Value) {
    match map.get(df.columns, name) {
      None => (name, val.vnull()),
      Some(c) => (name, col.col_nth(c, idx)),
    }
  })
}

# head / tail / slice_rows dispatch to the zero-copy arrow kernels
# on arrow-backed frames (RecordBatch::slice — no data copied), and
# to the legacy pick_rows walk on list-backed frames. Pre-#19 the
# legacy walk ran on both backings and silently produced empty rows
# on arrow frames.
fn head(df :: DataFrame, n :: Int) -> DataFrame {
  match df.arrow_table {
    Some(t) => with_arrow_table(df, arrow.head(t, n), prov.op_head(n)),
    None => {
      let actual := if n > df.nrows {
        df.nrows
      } else {
        n
      }
      let df2 := pick_rows(df, range_list(0, actual))
      { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows, provenance: list.cons(prov.op_head(n), df.provenance), arrow_table: df2.arrow_table }
    },
  }
}

fn tail(df :: DataFrame, n :: Int) -> DataFrame {
  match df.arrow_table {
    Some(t) => with_arrow_table(df, arrow.tail(t, n), prov.op_tail(n)),
    None => {
      let start := if n >= df.nrows {
        0
      } else {
        df.nrows - n
      }
      let df2 := pick_rows(df, range_list(start, df.nrows))
      { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows, provenance: list.cons(prov.op_tail(n), df.provenance), arrow_table: df2.arrow_table }
    },
  }
}

# `arrow.slice(t, start, stop)` is (start, stop-exclusive) — same
# contract as the legacy path below.
fn slice_rows(df :: DataFrame, start :: Int, stop :: Int) -> DataFrame {
  match df.arrow_table {
    Some(t) => with_arrow_table(df, arrow.slice(t, start, stop), prov.op_slice(start, stop)),
    None => {
      let actual_stop := if stop > df.nrows {
        df.nrows
      } else {
        stop
      }
      let df2 := pick_rows(df, range_list(start, actual_stop))
      { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows, provenance: list.cons(prov.op_slice(start, stop), df.provenance), arrow_table: df2.arrow_table }
    },
  }
}

fn add_column(df :: DataFrame, name :: Str, vals :: List[val.Value]) -> Result[DataFrame, FrameError] {
  if list.len(vals) != df.nrows {
    Err(frame_err("FRAME_LENGTH_MISMATCH", str.concat("column '", str.concat(name, "' has wrong length")), name))
  } else {
    let new_names := list.reverse(list.cons(name, list.reverse(df.col_names)))
    Ok({ col_names: new_names, columns: map.set(df.columns, name, col.col_from_values(vals)), nrows: df.nrows, provenance: list.cons(prov.op_add_column(name), df.provenance), arrow_table: None })
  }
}

fn add_typed_column(df :: DataFrame, name :: Str, c :: col.Col) -> Result[DataFrame, FrameError] {
  if col.col_len(c) != df.nrows {
    Err(frame_err("FRAME_LENGTH_MISMATCH", str.concat("column '", str.concat(name, "' has wrong length")), name))
  } else {
    let new_names := list.reverse(list.cons(name, list.reverse(df.col_names)))
    Ok({ col_names: new_names, columns: map.set(df.columns, name, c), nrows: df.nrows, provenance: list.cons(prov.op_add_column(name), df.provenance), arrow_table: None })
  }
}

fn drop_column(df :: DataFrame, name :: Str) -> Result[DataFrame, FrameError] {
  let missing := list.fold(df.col_names, true, fn (acc :: Bool, n :: Str) -> Bool {
    acc and n != name
  })
  if missing {
    Err(not_found_error(name))
  } else {
    let new_names := list.filter(df.col_names, fn (n :: Str) -> Bool {
      n != name
    })
    Ok({ col_names: new_names, columns: df.columns, nrows: df.nrows, provenance: list.cons(prov.op_drop([name]), df.provenance), arrow_table: None })
  }
}

fn pipe(df :: DataFrame, step_name :: Str, transform :: (DataFrame) -> DataFrame) -> DataFrame {
  let df2 := transform(df)
  { col_names: df2.col_names, columns: df2.columns, nrows: df2.nrows, provenance: list.cons(prov.op_pipe(step_name), df2.provenance), arrow_table: df2.arrow_table }
}

