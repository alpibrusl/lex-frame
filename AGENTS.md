# lex-frame — Agent Guide

This document is written for AI agents consuming `lex-frame`. It covers the
design decisions that make the library agent-first, the canonical patterns for
every operation, and the conventions an agent must follow.

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
  col_names  :: List[Str]          -- ordered column names
  columns    :: Map[Str, List[Value]]  -- column-oriented storage
  nrows      :: Int
  provenance :: List[Op]           -- immutable audit trail
}

FrameError = {
  code    :: Str   -- machine-readable, e.g. "FRAME_LENGTH_MISMATCH"
  message :: Str   -- human-readable description
  context :: Str   -- which column / index caused the error
}
```

---

## Error handling

Every fallible function returns `Result[DataFrame, FrameError]`.
Always match on the result — never assume `Ok`.

```lex
match frame.from_columns(cols) {
  Ok(df)  => ...
  Err(e)  =>
    // Branch on e.code, not on e.message (message wording may change)
    if e.code == "FRAME_LENGTH_MISMATCH" { ... } else { ... }
}
```

### Error code catalogue

| Code | Module | Meaning |
|---|---|---|
| `FRAME_LENGTH_MISMATCH` | frame | Columns have different lengths |
| `FRAME_COLUMN_NOT_FOUND` | frame | Column name does not exist |
| `FRAME_DUPLICATE_COLUMN` | frame | Duplicate column name |
| `SELECT_UNKNOWN_COLUMN` | select | Requested column not in DataFrame |
| `SELECT_COLUMN_NOT_FOUND` | select | filter_col target column missing |
| `GROUP_UNKNOWN_KEY` | group | Key column not in DataFrame |
| `GROUP_UNKNOWN_AGG_COL` | group | Aggregation column not in DataFrame |
| `JOIN_KEY_NOT_IN_LEFT` | join | Join key missing from left DataFrame |
| `JOIN_KEY_NOT_IN_RIGHT` | join | Join key missing from right DataFrame |
| `IO_EMPTY_INPUT` | io | CSV string is empty |
| `IO_READ_FAILED` | io | Filesystem read error |
| `IO_WRITE_FAILED` | io | Filesystem write error |

---

## Context-window-efficient output

Never pass a raw DataFrame to an LLM. Use the inspect module:

```lex
// Compact JSON with schema + up to N sample rows
let payload = inspect.to_json_payload(df, 5)

// GitHub-flavored Markdown table
let table = inspect.to_markdown(df, 20)

// Full narrative summary (shape, types, null counts, provenance)
let summary = inspect.summary(df)

// Per-column stats (for targeted analysis)
let profile = inspect.column_profile(df, "price")
```

---

## Provenance / audit trail

Every transform records an `Op` in `df.provenance`. Read it with:

```lex
let history = inspect.history(df)
// Returns numbered list:
// 1. load: source="users.csv" rows=1000
// 2. filter: predicate="age > 18" kept=823
// 3. sort: column="salary" asc=false
```

You can also use the named pipe combinator to label your own steps:

```lex
let df2 = frame.pipe(df, "normalize_salaries", fn(d) -> frame.DataFrame {
  // ... transform ...
  d
})
```

---

## Common patterns

### Build a DataFrame

```lex
import "std.list" as list
import "src/value" as val
import "src/frame" as frame

let cols = list.cons(
  ("name", list.cons(val.VStr("Alice"), list.cons(val.VStr("Bob"), []))),
  list.cons(
    ("age",  list.cons(val.VInt(28),    list.cons(val.VInt(34), []))),
    []
  )
)
match frame.from_columns(cols) {
  Ok(df)  => ...
  Err(e)  => handle_error(e)
}
```

### Filter rows

```lex
import "src/select" as sel

let pred = fn(row) -> Bool {
  match sel.row_get_or_null(row, "age") {
    val.VInt(n) => n >= 18
    _ => false
  }
}
match sel.filter_rows(df, "age >= 18", pred) {
  Ok(filtered) => ...
  Err(e)       => handle_error(e)
}
```

### Group by + aggregate

```lex
import "src/group" as grp

let specs = list.cons(
  { col_name = "revenue", op = grp.AggSum,  result_name = "total_revenue" },
  list.cons(
    { col_name = "revenue", op = grp.AggMean, result_name = "avg_revenue" },
    []
  )
)
match grp.group_by(df, list.cons("region", [])) {
  Err(e)  => handle_error(e)
  Ok(gf)  => match grp.agg(gf, specs) {
    Err(e)   => handle_error(e)
    Ok(result) => ...
  }
}
```

### Sort

```lex
import "src/sort" as srt

let sorted = srt.sort_by(df, "score", false)  // false = descending
```

### Parallel column transform

```lex
import "src/dist" as dist
import "std.math" as math

let normed = dist.par_apply_col(df, "price", fn(v) -> val.Value {
  match val.as_float(v) {
    Some(f) => val.VFloat(f / 100.0)
    None    => v
  }
})
```

---

## Lex language sharp edges

- **All values are immutable.** Every transform returns a new DataFrame.
- **Effects are declared.** `read_csv` has effect `[fs.read]`; calling it from
  a pure function is a type error.
- **No exceptions.** Errors are `Result` values; you must handle them.
- **`list.cons` + `list.reverse`** for O(n) list building; avoid
  `list.concat(acc, [v])` in loops (O(n²)).
- **`val.VNull`** represents missing data. `val.is_null(v)` to test.
  Aggregations skip nulls by default.

---

## Module map

| Module | Purpose |
|---|---|
| `src/value` | Core `Value` ADT (VInt, VFloat, VStr, VBool, VNull) |
| `src/frame` | DataFrame type, construction, slicing |
| `src/select` | Column select/drop/rename, row filter, derived columns |
| `src/agg` | Column-level aggregations (sum, mean, min, max, std, …) |
| `src/group` | GroupBy and multi-agg |
| `src/join` | inner\_join, left\_join, cross\_join |
| `src/sort` | sort\_by, sort\_by\_cols (merge sort) |
| `src/io` | CSV / JSON parse and render; `[fs.read]`/`[fs.write]` I/O |
| `src/stats` | describe, correlation, null\_counts |
| `src/inspect` | Agent-optimised output: summary, to\_markdown, to\_json\_payload |
| `src/provenance` | Op ADT and render helpers |
| `src/dist` | Parallel transforms via `list.par_map` |
