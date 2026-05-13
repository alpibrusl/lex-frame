# Op ADT — immutable audit trail embedded in every DataFrame.
# Every transform appends one Op; agents read the history via inspect.history.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list

type Op =
    OpLoad(Str, Int)      # source, nrows
  | OpFilter(Str, Int)    # predicate_desc, kept_rows
  | OpSelect(List[Str])   # kept_cols
  | OpDrop(List[Str])     # dropped_cols
  | OpRename(Str, Str)    # old_name, new_name
  | OpAddColumn(Str)      # new_col_name
  | OpSort(Str, Bool)     # col, asc
  | OpGroupBy(List[Str])  # key_cols
  | OpJoin(Str, Str)      # join_type, key_col
  | OpHead(Int)
  | OpTail(Int)
  | OpSlice(Int, Int)     # start, stop
  | OpPipe(Str)           # step_name

fn op_load(source :: Str, nrows :: Int) -> Op        { OpLoad(source, nrows) }
fn op_filter(desc :: Str, kept :: Int) -> Op         { OpFilter(desc, kept) }
fn op_select(cols :: List[Str]) -> Op                { OpSelect(cols) }
fn op_drop(cols :: List[Str]) -> Op                  { OpDrop(cols) }
fn op_rename(old :: Str, new :: Str) -> Op           { OpRename(old, new) }
fn op_add_column(col :: Str) -> Op                   { OpAddColumn(col) }
fn op_sort(col :: Str, asc :: Bool) -> Op            { OpSort(col, asc) }
fn op_group_by(keys :: List[Str]) -> Op              { OpGroupBy(keys) }
fn op_join(jtype :: Str, key :: Str) -> Op           { OpJoin(jtype, key) }
fn op_head(n :: Int) -> Op                           { OpHead(n) }
fn op_tail(n :: Int) -> Op                           { OpTail(n) }
fn op_slice(start :: Int, stop :: Int) -> Op         { OpSlice(start, stop) }
fn op_pipe(name :: Str) -> Op                        { OpPipe(name) }

fn render_op(op :: Op) -> Str {
  match op {
    OpLoad(src, n)       =>
      str.concat("load: source=\"", str.concat(src, str.concat("\" rows=", int.to_str(n)))),
    OpFilter(desc, kept) =>
      str.concat("filter: predicate=\"", str.concat(desc, str.concat("\" kept=", int.to_str(kept)))),
    OpSelect(cols)       =>
      str.concat("select: cols=[", str.concat(str.join(cols, ","), "]")),
    OpDrop(cols)         =>
      str.concat("drop: cols=[", str.concat(str.join(cols, ","), "]")),
    OpRename(old, new)   =>
      str.concat("rename: ", str.concat(old, str.concat(" -> ", new))),
    OpAddColumn(col)     => str.concat("add_column: ", col),
    OpSort(col, asc)     =>
      str.concat("sort: column=\"", str.concat(col, str.concat("\" asc=", if asc { "true" } else { "false" }))),
    OpGroupBy(keys)      =>
      str.concat("group_by: keys=[", str.concat(str.join(keys, ","), "]")),
    OpJoin(jtype, key)   =>
      str.concat("join: type=", str.concat(jtype, str.concat(" key=", key))),
    OpHead(n)            => str.concat("head: n=", int.to_str(n)),
    OpTail(n)            => str.concat("tail: n=", int.to_str(n)),
    OpSlice(s, e)        =>
      str.concat("slice: start=", str.concat(int.to_str(s), str.concat(" stop=", int.to_str(e)))),
    OpPipe(name)         => str.concat("pipe: step=\"", str.concat(name, "\"")),
  }
}

fn render_history(ops :: List[Op]) -> Str {
  let indexed := list.enumerate(ops)
  let lines := list.map(indexed, fn (pair :: (Int, Op)) -> Str {
    match pair { (i, op) => str.concat(int.to_str(i + 1), str.concat(". ", render_op(op))) }
  })
  str.join(lines, "\n")
}
