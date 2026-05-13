# lex-frame — operation provenance log
#
# Every DataFrame carries a List[Op] recording what happened to it.
# This is the audit trail that makes lex-frame AI-agent-friendly:
# an agent can always call history(df) to explain its own work.
#
# Op variants are flat (no recursive nesting) as required by Lex.
# Each variant carries only primitive metadata, not the full frame.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list

type Op =
    OpLoad({ source :: Str, rows :: Int })
  | OpFilter({ predicate :: Str, kept :: Int })
  | OpSelect({ cols :: List[Str] })
  | OpDrop({ cols :: List[Str] })
  | OpRename({ from_col :: Str, to_col :: Str })
  | OpAddColumn({ name :: Str, expr :: Str })
  | OpSort({ col :: Str, ascending :: Bool })
  | OpGroupBy({ col :: Str, n_groups :: Int })
  | OpJoin({ on :: Str, kind :: Str, result_rows :: Int })
  | OpHead({ n :: Int })
  | OpTail({ n :: Int })
  | OpSlice({ from_row :: Int, to_row :: Int })
  | OpPipe({ name :: Str })

# Constructors — call these instead of inline record literals.
fn op_load(source :: Str, rows :: Int)           -> Op { OpLoad({ source: source, rows: rows }) }
fn op_filter(predicate :: Str, kept :: Int)       -> Op { OpFilter({ predicate: predicate, kept: kept }) }
fn op_select(cols :: List[Str])                   -> Op { OpSelect({ cols: cols }) }
fn op_drop(cols :: List[Str])                     -> Op { OpDrop({ cols: cols }) }
fn op_rename(from_col :: Str, to_col :: Str)      -> Op { OpRename({ from_col: from_col, to_col: to_col }) }
fn op_add_col(name :: Str, expr :: Str)           -> Op { OpAddColumn({ name: name, expr: expr }) }
fn op_sort(col :: Str, ascending :: Bool)         -> Op { OpSort({ col: col, ascending: ascending }) }
fn op_group_by(col :: Str, n_groups :: Int)       -> Op { OpGroupBy({ col: col, n_groups: n_groups }) }
fn op_join(on :: Str, kind :: Str, result_rows :: Int) -> Op { OpJoin({ on: on, kind: kind, result_rows: result_rows }) }
fn op_head(n :: Int)                              -> Op { OpHead({ n: n }) }
fn op_tail(n :: Int)                              -> Op { OpTail({ n: n }) }
fn op_slice(from_row :: Int, to_row :: Int)       -> Op { OpSlice({ from_row: from_row, to_row: to_row }) }
fn op_pipe(name :: Str)                           -> Op { OpPipe({ name: name }) }

# Render a single Op as a human-readable step.
fn render_op(op :: Op) -> Str {
  match op {
    OpLoad(d)      => str.concat("LOAD ", str.concat(d.source, str.concat(" (", str.concat(int.to_str(d.rows), " rows)")))),
    OpFilter(d)    => str.concat("FILTER ", str.concat(d.predicate, str.concat(" → ", str.concat(int.to_str(d.kept), " rows kept")))),
    OpSelect(d)    => str.concat("SELECT [", str.concat(str.join(d.cols, ", "), "]")),
    OpDrop(d)      => str.concat("DROP [", str.concat(str.join(d.cols, ", "), "]")),
    OpRename(d)    => str.concat("RENAME ", str.concat(d.from_col, str.concat(" → ", d.to_col))),
    OpAddColumn(d) => str.concat("ADD_COLUMN ", str.concat(d.name, str.concat(" := ", d.expr))),
    OpSort(d)      => str.concat("SORT BY ", str.concat(d.col, if d.ascending { " ASC" } else { " DESC" })),
    OpGroupBy(d)   => str.concat("GROUP_BY ", str.concat(d.col, str.concat(" (", str.concat(int.to_str(d.n_groups), " groups)")))),
    OpJoin(d)      => str.concat("JOIN ON ", str.concat(d.on, str.concat(" [", str.concat(d.kind, str.concat("] → ", str.concat(int.to_str(d.result_rows), " rows")))))),
    OpHead(d)      => str.concat("HEAD ", int.to_str(d.n)),
    OpTail(d)      => str.concat("TAIL ", int.to_str(d.n)),
    OpSlice(d)     => str.concat("SLICE ", str.concat(int.to_str(d.from_row), str.concat(":", int.to_str(d.to_row)))),
    OpPipe(d)      => str.concat("PIPE ", d.name),
  }
}

# Render full provenance as numbered steps. Used by inspect.history.
fn render_history(ops :: List[Op]) -> Str {
  if list.is_empty(ops) { "(no history)" }
  else {
    let numbered := list.map(list.enumerate(ops), fn (p :: (Int, Op)) -> Str {
      let i  := match p { (a, _) => a }
      let op := match p { (_, b) => b }
      str.concat(int.to_str(i + 1), str.concat(". ", render_op(op)))
    })
    str.join(numbered, "\n")
  }
}
