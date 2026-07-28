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
| `src/value` | `Value` ADT — int/float/str/bool/null; parse, compare, convert (`vint`, `vstr`, `as_int`, …) |
| `src/col` | Typed `Col` storage (8 variants incl. nullable); kernels the legacy ops run on |
| `src/frame` | `DataFrame` type; construction, slicing (`head`, `tail`, `slice`), add/drop column; arrow backing |
| `src/select` | Column select/drop/rename; row filter; derived columns; **fast filters** (int/float/str eq-gt-lt, `filter_in_str_fast`, `filter_isnull/notnull_fast`, `drop_nulls_fast`) |
| `src/agg` | Null-aware column aggregations; **fast reductions** (`sum_col_fast`, `mean_col_fast`, …) |
| `src/group` | `group_by` + 9-variant `AggOp`; `value_counts`; **`group_agg_fast` / multi-key `group_agg_by_keys_fast`** (one Polars call) |
| `src/join` | `inner_join`, `left_join`, `cross_join`; **`inner_join_fast` / `left_join_fast`** |
| `src/sort` | `sort_by`, `sort_by_cols` via merge sort; **`sort_by_fast`** |
| `src/io` | CSV / JSON-rows parse+render; `read_csv_fast` / `write_csv_fast`; **Parquet** (`read_parquet`, `write_parquet`) |
| `src/stats` | `describe` (5-row summary), Pearson `correlation`, `null_counts` |
| `src/inspect` | `summary`, `to_markdown`, `to_json_payload`, `column_profile`, `history`, `sample_rows`, `null_report` |
| `src/provenance` | 13-variant `Op` ADT; embedded in every `DataFrame` |
| `src/lazy` | **Lazy query plans** — record ops, optimize (filter hoisting, projection pruning), execute on `collect` |
| `src/dist` | Chunked column/row transforms + cost estimation (sequential today; the fast path parallelises in Polars instead) |

## Performance: the columnar fast path

`lex-frame` has two engines behind one API:

- **Legacy list engine** — columns are typed Lex lists (`src/col`),
  every op runs in interpreted bytecode. Fully general (closures,
  nullable bools, row API), but O(n²) on row-indexed ops and ~3-4
  orders of magnitude slower than pandas at scale.
- **Columnar fast path** — the `DataFrame` carries an
  `arrow_table :: Option[Table]` backing. When present, `_fast` ops
  dispatch to `std.arrow` / `std.df` (Arrow + Polars kernels, one
  native call per op). At 1M rows this is **competitive with pandas**
  (see `bench/REPORT.md`).

Build arrow-backed frames with `io.read_csv_fast`, `io.read_parquet`,
or `frame.from_arrow_table`; then stay on the `_fast` ops:

```lex
import "./src/io"     as fio
import "./src/select" as sel
import "./src/sort"   as srt
import "./src/group"  as grp

fn pipeline(path :: Str) -> [fs_read] Result[frame.DataFrame, frame.FrameError] {
  match fio.read_csv_fast(path) {
    Err(e) => Err(e),
    Ok(df) => match sel.filter_gt_int_fast(df, "x", 100) {
      Err(e) => Err(e),
      Ok(hot) => grp.group_agg_fast(srt.sort_by_fast(hot, "x", false), "g",
        [grp.agg_spec("total", "x", grp.agg_sum())]),
    },
  }
}
```

Every `_fast` op falls back to the legacy engine on a list-backed
frame, so one code path works for both. Full example:
`examples/06_fast_pipeline.lex`.

**Sharp edges** (see issues #6 and #19):

- An arrow-backed frame's legacy `columns` map is **empty**. Since
  #19 no public op silently returns empty/wrong data because of it:
  ops with kernel equivalents produce correct results on both
  backings, and the rest refuse with `FRAME_LEGACY_ONLY`. The full
  status per op:

  | Status on an arrow-backed frame | Ops |
  |---|---|
  | **Kernel-backed** (correct on both backings) | all `_fast` ops; `frame.head/tail/slice_rows`; `sort.sort_by`; `select.select_cols/drop_cols`; `group.value_counts`; `join.inner_join/left_join`; `agg.sum_col/mean_col/min_col/max_col/count_all/count_non_null`; `stats.null_counts`; `inspect.summary/infer_dtypes/column_profile/sample_rows/null_report/history`; the whole `lazy` module |
  | **Refuses with `FRAME_LEGACY_ONLY`** | `select.filter_rows/with_column/rename_col`; `group.group_by`; `join.cross_join`; `dist.par_apply_col/par_map_rows`; `io.write_csv` |
  | **Explicit marker instead of rows** | `inspect.to_markdown/to_json_payload` render schema + a "not materialized" note (row values need the legacy map) |
  | **Degraded, visible** | `agg.min_col/max_col` are int-kernel-only (`None` on float/utf8 arrow columns); `agg.variance_col/std_col/n_distinct` return `None`/`0` (no kernel yet); `sample_rows` is first-n, not strided; `stats.describe/correlation` and `dist.par_apply_all_cols/par_filter_rows` still walk the legacy map — materialize first or stay list-backed |

- Mixing backings in a join is an error (`JOIN_MIXED_BACKING`)
  rather than a silent empty result.
- `group_agg_fast` / `group_agg_by_keys_fast` support `sum | mean |
  min | max | count | n_distinct`; `std` / `var` / `count_non_null`
  still need the legacy engine (`GROUP_UNSUPPORTED_FAST_AGG`).
  Multi-key group-by is fast-path only — on a list-backed frame it
  returns `GROUP_MULTI_KEY_NEEDS_ARROW`.
- Arrow constructors cover int64 / float64 / utf8 columns; bool and
  nullable construction from Lex lists stays on the legacy engine.

### Lazy plans

`src/lazy` layers a query planner over the same kernels: build a
`Plan` (no execution), run it with `collect` (scan sources; effect
`[fs_read]`) or `collect_frame` (in-memory sources; pure). At
collect time the plan is rewritten — every filter runs before
sorts/selects in its segment, and when the plan narrows (a `select`
or `group_agg`), untouched columns are pruned at the source. For
`scan_parquet` the projection is pushed into the reader itself:
H2O q2 over a 9-column parquet file drops from 323 ms to 177 ms
because only 3 columns are decoded (`bench/REPORT.md`).

```lex
import "./src/lazy"  as lazy
import "./src/group" as grp

fn q2(path :: Str) -> [fs_read] Result[frame.DataFrame, frame.FrameError] {
  lazy.collect(lazy.group_agg(lazy.scan_parquet(path),
    ["id1", "id2"], [grp.agg_spec("v1_sum", "v1", grp.agg_sum())]))
}
```

`lazy.explain(plan)` renders the rewritten plan (one line per op) so
you can see what `collect` will actually run. Semantics differences
from eager, by design: a filter placed after the `select` that drops
its column still works (it's hoisted above), and a misspelled column
anywhere in a pruned plan is a loud `SELECT_UNKNOWN_COLUMN` instead
of eager's silent sort no-op. Sort tie order is not guaranteed when
filters hoist across a sort (Polars default).

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
| `FRAME_COLUMN_NOT_FOUND` | frame, select, group, join | Column name not in DataFrame (join errors carry `left.`/`right.` context) |
| `SELECT_UNKNOWN_COLUMN` | select | Requested column missing (`select_cols`, `drop_cols`, fast filters) |
| `GROUP_UNKNOWN_KEY` | group | Fast group-by key column not in the arrow table |
| `GROUP_UNSUPPORTED_FAST_AGG` | group | `std`/`var`/`count_non_null` requested via `group_agg_fast` on an arrow-backed frame |
| `GROUP_MULTI_KEY_NEEDS_ARROW` | group | Multi-key `group_agg_by_keys_fast` on a list-backed frame |
| `JOIN_MIXED_BACKING` | join | One side arrow-backed, the other list-backed in a join |
| `FRAME_LEGACY_ONLY` | frame, select, group, join, dist, io, lazy | A legacy-engine-only op (closure filter/derive, `rename_col`, `group_by`, `cross_join`, `dist.par_*`, legacy `write_csv`) called on an arrow-backed frame — the message names the fast alternative |
| `LAZY_SOURCE_NEEDS_READ` | lazy | `collect_frame` (the pure entry point) called on a plan that scans a file — use `collect` |
| `IO_EMPTY_INPUT` | io | CSV string is empty |
| `IO_READ_FAILED` | io | Filesystem / arrow read error |
| `IO_WRITE_FAILED` | io | Filesystem / arrow write error, or a fast writer given a list-backed frame |

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
| `05_distributed.lex` | `par_apply_col`, `par_filter_rows`, cost estimation |
| `06_fast_pipeline.lex` | Columnar fast path: `read_csv_fast` → fast filter/sort/group → `write_csv_fast` |

## Running tests

```bash
lex test
# 13 passed, 0 failed
```

Requires lex v0.10.7 (the version pinned in `lex.toml` and CI; `std.arrow` / `std.df` fast paths need >= 0.10.0).

---

Built under the principles of [Trust Without Comprehension](https://lexlang.org/manifesto).
