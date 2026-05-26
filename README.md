# lex-frame

A column-oriented dataframe library for [Lex](https://github.com/alpibrusl/lex-lang),
designed from the ground up for AI-agent consumption.

## Why

Existing dataframe libraries (pandas, polars, spark) are hostile to LLM agents:

| Problem | Agent impact |
|---|---|
| Exceptions on bad input | Unstructured stack traces, no machine-readable error code |
| Mutable state | Agent rewrites corrupt shared data |
| Verbose `repr()` | Wastes context tokens, no schema info |
| No lineage | Agent cannot explain or audit what happened |

`lex-frame` fixes all four:

- **`Result`-typed errors with stable codes** — branch on `e.code`, not fragile message strings
- **Immutable DataFrames** — every transform returns a new value; concurrent agent access is safe
- **`inspect` module** — `to_json_payload`, `to_markdown`, `summary` sized to fit LLM context windows
- **Provenance trail** — every transform appends a typed `Op`; `inspect.history(df)` returns a numbered audit trail

## Quick start

```lex
import "std.list"      as list
import "./src/value"   as val
import "./src/frame"   as frame
import "./src/select"  as sel
import "./src/inspect" as inspect

fn main() -> Str {
  let cols := list.cons(
    ("name",   list.cons(val.vstr("Alice"), list.cons(val.vstr("Bob"), []))),
    list.cons(
    ("salary", list.cons(val.vint(95000),  list.cons(val.vint(72000), []))),
    [])
  )
  match frame.from_columns(cols) {
    Err(e)  => e.message,
    Ok(df)  => inspect.to_markdown(df, 10),
  }
}
```

## Modules

| Module | Purpose |
|---|---|
| `src/value` | `Value` ADT — `VInt`, `VFloat`, `VStr`, `VBool`, `VNull`; parse, compare, convert |
| `src/frame` | `DataFrame` type; construction, slicing (`head`, `tail`, `slice`), add/drop column |
| `src/select` | Column select/drop/rename; row filter; derived columns (`with_column`) |
| `src/agg` | Null-aware column aggregations — `sum`, `mean`, `min`, `max`, `std`, `variance`, `n_distinct` |
| `src/group` | `group_by` + 9-variant `AggOp`; `value_counts` convenience |
| `src/join` | `inner_join`, `left_join`, `cross_join` with `_right` suffix disambiguation |
| `src/sort` | `sort_by`, `sort_by_cols` via merge sort on argsort indices |
| `src/io` | CSV and JSON-rows parse/render; `read_csv [io]` / `write_csv [io]` |
| `src/stats` | `describe` (5-row summary), Pearson `correlation`, `null_counts` |
| `src/inspect` | `summary`, `to_markdown`, `to_json_payload`, `column_profile`, `history`, `sample_rows`, `null_report` |
| `src/provenance` | 13-variant `Op` ADT; embedded in every `DataFrame` |
| `src/dist` | Parallel column/row transforms via `list.par_map`; cost estimation |

## Error handling

Every fallible function returns `Result[DataFrame, FrameError]`:

```lex
type FrameError = {
  code    :: Str,   # stable machine-readable code
  message :: Str,   # human-readable description
  context :: Str,   # column name or index that triggered the error
}
```

Branch on `e.code`, not `e.message`:

```lex
match sel.drop_col(df, "nonexistent") {
  Ok(df2) => ...,
  Err(e)  => if e.code == "FRAME_COLUMN_NOT_FOUND" { recover() } else { fail(e) },
}
```

### Error code catalogue

| Code | Module | Trigger |
|---|---|---|
| `FRAME_LENGTH_MISMATCH` | frame | Columns have different row counts |
| `FRAME_COLUMN_NOT_FOUND` | frame | Column name not in DataFrame |
| `FRAME_DUPLICATE_COLUMN` | frame | Duplicate column name in construction |
| `SELECT_UNKNOWN_COLUMN` | select | Requested column missing |
| `GROUP_UNKNOWN_KEY` | group | Key column not in DataFrame |
| `JOIN_KEY_NOT_IN_LEFT` | join | Join key missing from left frame |
| `JOIN_KEY_NOT_IN_RIGHT` | join | Join key missing from right frame |
| `IO_EMPTY_INPUT` | io | CSV string is empty |
| `IO_READ_FAILED` | io | Filesystem read error |
| `IO_WRITE_FAILED` | io | Filesystem write error |

## Agent-first output

Never paste a raw DataFrame into an LLM prompt. Use the `inspect` module:

```lex
# Compact JSON — schema + N sample rows, sized for LLM context windows
let payload := inspect.to_json_payload(df, 5)

# GitHub-flavored Markdown table
let table := inspect.to_markdown(df, 20)

# Narrative summary: shape, column types, null counts, provenance
let summary := inspect.summary(df)

# Per-column stats (mean, std, min, max, nulls, n_distinct)
let profile := inspect.column_profile(df, "price")

# Numbered audit trail of every transform applied
let history := inspect.history(df)
```

## Provenance

Every operation appends a typed `Op` to `df.provenance`. Example trail:

```
1. load: source="sales.csv" rows=10000
2. filter: predicate="region == EU" kept=3241
3. group_by: keys=["product"]
4. sort: column="revenue" asc=false
```

Label your own pipeline stages:

```lex
let df2 := frame.pipe(df, "normalize_prices", fn (d :: frame.DataFrame) -> frame.DataFrame {
  # ... transform ...
  d
})
```

## Group by and aggregate

```lex
import "./src/group" as grp

let specs := list.cons(
  grp.agg_spec("total", "revenue", grp.agg_sum()),
  list.cons(grp.agg_spec("avg", "revenue", grp.agg_mean()), [])
)
match grp.group_by(df, "region") {
  Err(e)  => handle(e),
  Ok(gf)  => {
    let result := grp.agg(gf, specs)
    inspect.to_markdown(result, 50)
  },
}
```

Available `AggOp` constructors: `agg_sum`, `agg_mean`, `agg_min`, `agg_max`,
`agg_count`, `agg_count_non_null`, `agg_std`, `agg_var`, `agg_n_distinct`.

## Effect annotations

Functions that touch the filesystem declare it in their type:

```lex
fn read_csv(path :: Str)                   -> [io] Result[DataFrame, FrameError]
fn write_csv(path :: Str, df :: DataFrame) -> [io] Result[Unit, FrameError]
```

Callers must also declare `[io]` or grant the effect at `lex run`:

```bash
lex run --allow-effects io my_script.lex main
```

## Examples

Runnable examples are in `examples/`:

| File | Demonstrates |
|---|---|
| `01_basics.lex` | Construction, filter, sort, inspect output |
| `02_agent_workflow.lex` | Error-code branching, provenance, `to_json_payload` |
| `03_group_and_join.lex` | `group_by` + `agg`, `inner_join`, `left_join` |
| `04_csv_analysis.lex` | `read_csv`, `describe`, `correlation`, `null_report` |
| `05_distributed.lex` | `par_apply_col`, `par_apply_rows`, cost estimation |

## Running tests

```bash
lex test
# 11 passed, 0 failed
```

Requires lex v0.9.2 or later.

---

Built under the principles of [Trust Without Comprehension](https://alpibru.com/manifesto).
