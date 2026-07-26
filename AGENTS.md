# lex-frame — Agent Guide

This document is written for AI agents consuming `lex-frame`. It covers the
design decisions that make the library agent-first, the canonical patterns for
every operation, and the conventions an agent must follow.

For the language-wide idiom rules (effect discipline, repair-not-regenerate,
`examples {}` blocks, stdlib-first), run `lex agent-guidelines` — this file
only covers what is specific to `lex-frame`.

---

## Why lex-frame exists

Dataframe libraries designed for humans (pandas, polars, spark) are hostile to
LLM agents:

| Problem | Human workaround | Agent impact |
|---|---|---|
| Exceptions on bad input | try/except | Unstructured stack traces, no machine-readable code |
| Mutable state | careful copy discipline | Agent rewrites corrupt shared state |
| `repr()` output | visual inspection | Too verbose, no schema, wastes context tokens |
| No lineage | manual logging | Agent cannot explain what happened |
| Opaque type coercion | docs + trial/error | Silent wrong answers |

`lex-frame` addresses all of these.

---

## Core types

```
DataFrame = {
  col_names   :: List[Str]            -- ordered column names
  columns     :: Map[Str, col.Col]    -- typed columnar storage (legacy engine)
  nrows       :: Int
  provenance  :: List[prov.Op]        -- immutable audit trail
  arrow_table :: Option[Table]        -- columnar backing for the fast path
}

FrameError = {
  code    :: Str   -- machine-readable, e.g. "FRAME_LENGTH_MISMATCH"
  message :: Str   -- human-readable description
  context :: Str   -- which column / index caused the error
}
```

`Col` (in `src/col`) is an 8-variant typed column ADT (`IntCol`,
`FloatCol`, `StrCol`, `BoolCol` + nullable variants). Agents rarely touch
it directly — build frames from `List[val.Value]` pairs or from arrow
tables and let the library pick storage.

---

## Two engines — pick per data size

- **Legacy list engine** (default): fully general — closures, bools,
  nullables, row API. Fine to ~1k rows; O(n²) row ops beyond that.
- **Columnar fast path**: when `df.arrow_table` is `Some`, the `_fast`
  ops run as single `std.arrow` / `std.df` (Arrow/Polars) kernel calls.
  Competitive with pandas at 1M rows (`bench/REPORT.md`).

Build arrow-backed frames via `io.read_csv_fast` (`[fs_read]`),
`io.read_parquet` (`[fs_read]`), or `frame.from_arrow_table`. Every
`_fast` op falls back to the legacy engine on a list-backed frame, so
call sites don't need to branch.

**MUST**: on an arrow-backed frame, stay on `_fast` ops end-to-end.
Its legacy `columns` map is empty, so closure-based ops
(`sel.filter_rows`, `sel.with_column`, `inspect.*`, `dist.*`) see no
data there. Get results out via `io.write_csv_fast` /
`io.write_parquet` or the `agg.*_fast` reductions.

| Operation | Legacy (any frame) | Fast (arrow-backed, falls back) |
|---|---|---|
| filter | `sel.filter_rows(df, desc, pred)` | `sel.filter_eq_int_fast` / `filter_gt_int_fast` / `filter_lt_int_fast` / `filter_eq_str_fast` |
| sort | `srt.sort_by(df, col, asc)` | `srt.sort_by_fast(df, col, asc)` |
| group+agg | `grp.group_by` then `grp.agg` | `grp.group_agg_fast(df, key, specs)` |
| join | `jn.inner_join` / `jn.left_join` | `jn.inner_join_fast` / `jn.left_join_fast` |
| reductions | `agg.sum_col`, `agg.mean_col`, … | `agg.sum_col_fast`, `agg.mean_col_fast`, … |
| CSV in/out | `fio.read_csv [io]` / `fio.write_csv [io]` | `fio.read_csv_fast [fs_read]` / `fio.write_csv_fast [fs_write]` |
| Parquet | — | `fio.read_parquet` / `read_parquet_cols` / `write_parquet` |

Fast-path limits (v1): `group_agg_fast` supports
`sum | mean | min | max | count | n_distinct` only; arrow construction
covers int64/float64/utf8 columns; joins refuse mixed backings
(`JOIN_MIXED_BACKING`) instead of silently returning empty.

---

## Error handling

Every fallible function returns `Result[DataFrame, FrameError]`.
Always match on the result — never assume `Ok`.

```lex
match frame.from_columns(cols) {
  Ok(df) => use_it(df),
  Err(e) =>
    # Branch on e.code, not on e.message (message wording may change)
    if e.code == "FRAME_LENGTH_MISMATCH" {
      recover()
    } else {
      fail(e)
    },
}
```

### Error code catalogue

| Code | Module | Meaning |
|---|---|---|
| `FRAME_LENGTH_MISMATCH` | frame | Columns have different lengths |
| `FRAME_COLUMN_NOT_FOUND` | frame, select, group, join | Column name does not exist (join errors carry `left.`/`right.` context) |
| `SELECT_UNKNOWN_COLUMN` | select | Requested column not in DataFrame (`select_cols`, fast filters) |
| `GROUP_UNKNOWN_KEY` | group | Fast group-by key not in the arrow table |
| `GROUP_UNSUPPORTED_FAST_AGG` | group | `std`/`var`/`count_non_null` via `group_agg_fast` on an arrow-backed frame |
| `JOIN_MIXED_BACKING` | join | `_fast` join given one arrow-backed and one list-backed frame |
| `IO_EMPTY_INPUT` | io | CSV string is empty |
| `IO_READ_FAILED` | io | Filesystem / arrow read error |
| `IO_WRITE_FAILED` | io | Filesystem / arrow write error, or fast writer given a list-backed frame |

---

## Context-window-efficient output

Never pass a raw DataFrame to an LLM. Use the inspect module (legacy
frames; for arrow-backed frames use the `agg.*_fast` reductions or
write out via `write_csv_fast` and sample the file):

```lex
# Compact JSON with schema + up to N sample rows
let payload := inspect.to_json_payload(df, 5)

# GitHub-flavored Markdown table
let table := inspect.to_markdown(df, 20)

# Full narrative summary (shape, types, null counts, provenance)
let summary := inspect.summary(df)

# Per-column stats (for targeted analysis)
let profile := inspect.column_profile(df, "price")
```

---

## Provenance / audit trail

Every transform — legacy and fast alike — records an `Op` in
`df.provenance`. Read it with:

```lex
let history := inspect.history(df)
# Returns numbered list:
# 1. load: source="users.csv" rows=1000
# 2. filter: predicate="age > 18" kept=823
# 3. sort: column="salary" asc=false
```

You can also use the named pipe combinator to label your own steps:

```lex
let df2 := frame.pipe(df, "normalize_salaries", fn (d :: frame.DataFrame) -> frame.DataFrame {
  # ... transform ...
  d
})
```

---

## Common patterns

### Build a DataFrame

```lex
import "std.list" as list
import "./src/value" as val
import "./src/frame" as frame

let cols := list.cons(
  ("name", list.cons(val.vstr("Alice"), list.cons(val.vstr("Bob"), []))),
  list.cons(
    ("age", list.cons(val.vint(28), list.cons(val.vint(34), []))),
    []
  )
)
match frame.from_columns(cols) {
  Ok(df) => use_it(df),
  Err(e) => handle_error(e),
}
```

### Filter rows (legacy closure API)

```lex
import "./src/select" as sel

let pred := fn (row :: List[(Str, val.Value)]) -> Bool {
  match val.as_int(sel.row_get_or_null(row, "age")) {
    Some(n) => n >= 18,
    None => false,
  }
}
match sel.filter_rows(df, "age >= 18", pred) {
  Ok(filtered) => use_it(filtered),
  Err(e) => handle_error(e),
}
```

For simple comparisons at scale, prefer the fast filters:
`sel.filter_gt_int_fast(df, "age", 17)`.

### Group by + aggregate

```lex
import "./src/group" as grp

let specs := list.cons(
  grp.agg_spec("total_revenue", "revenue", grp.agg_sum()),
  list.cons(grp.agg_spec("avg_revenue", "revenue", grp.agg_mean()), [])
)

# One call, either engine:
match grp.group_agg_fast(df, "region", specs) {
  Err(e) => handle_error(e),
  Ok(result) => use_it(result),
}

# Or the two-step legacy API (list-backed frames only):
match grp.group_by(df, "region") {
  Err(e) => handle_error(e),
  Ok(gf) => use_it(grp.agg(gf, specs)),
}
```

`AggOp` constructors: `agg_sum`, `agg_mean`, `agg_min`, `agg_max`,
`agg_count`, `agg_count_non_null`, `agg_std`, `agg_var`,
`agg_n_distinct`.

### Sort

```lex
import "./src/sort" as srt

let ranked := srt.sort_by_fast(df, "score", false)  # false = descending
```

### Columnar pipeline at scale

```lex
import "./src/io" as fio

fn top_regions(path :: Str) -> [fs_read] Result[frame.DataFrame, frame.FrameError] {
  match fio.read_csv_fast(path) {
    Err(e) => Err(e),
    Ok(df) => match sel.filter_gt_int_fast(df, "revenue", 0) {
      Err(e) => Err(e),
      Ok(hot) => grp.group_agg_fast(hot, "region",
        list.cons(grp.agg_spec("total", "revenue", grp.agg_sum()), [])),
    },
  }
}
```

---

## Lex language sharp edges

- **All values are immutable.** Every transform returns a new DataFrame.
- **Effects are declared.** Legacy `read_csv`/`write_csv` carry `[io]`
  (they go through `std.io`); the fast/parquet I/O carries the narrower
  `[fs_read]` / `[fs_write]` with per-path `--allow-fs-read` /
  `--allow-fs-write` scoping. Calling either from a pure fn is a type
  error. Note the run-time policy gate is per loaded module: a program
  that imports `src/io` needs `io` granted even if it only calls the
  fast fns (`lex run --allow-effects fs_read,fs_write,io …`).
- **No exceptions.** Errors are `Result` values; you must handle them.
- **`list.cons` + `list.reverse`** for O(n) list building; avoid
  `list.concat(acc, [v])` in loops (O(n²)).
- **`val.vnull()`** represents missing data; test with `val.is_null(v)`.
  Aggregations skip nulls by default.
- **Syntax**: bindings are `let x := e`, type annotations are `x :: T`,
  comments are `#`, match arms end with `,`. (Run `lex agent-guidelines`
  §2.6 for the full pitfall table.)

---

## Module map

| Module | Purpose |
|---|---|
| `src/value` | Core `Value` ADT; constructors `vint`/`vfloat`/`vstr`/`vbool`/`vnull`, accessors `as_int`/… |
| `src/col` | Typed `Col` storage (8 variants incl. nullable); legacy kernels |
| `src/frame` | DataFrame type, construction, slicing, arrow backing (`from_arrow_table`, `with_arrow_table`) |
| `src/select` | Column select/drop/rename, row filter, derived columns; fast filters |
| `src/agg` | Column-level aggregations (sum, mean, min, max, std, …) + `_fast` variants |
| `src/group` | GroupBy and multi-agg; `group_agg_fast` |
| `src/join` | inner\_join, left\_join, cross\_join; `_fast` joins |
| `src/sort` | sort\_by, sort\_by\_cols (merge sort); `sort_by_fast` |
| `src/io` | CSV / JSON parse and render; fast CSV + Parquet I/O |
| `src/stats` | describe, correlation, null\_counts |
| `src/inspect` | Agent-optimised output: summary, to\_markdown, to\_json\_payload |
| `src/provenance` | Op ADT and render helpers |
| `src/dist` | Chunked column/row transforms (sequential; fast path parallelises in Polars) |
