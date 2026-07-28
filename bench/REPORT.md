# lex-frame performance — 0.9.2 vs 0.9.3 (Unreleased) A/B

This file records a head-to-head run of `lex-frame` against two builds of
the `lex` runtime, on identical source code and identical input sizes.

- **0.9.2 (baseline)** — last release before the slice 2/3/4 work landed.
  Built from commit `b5e588a` (`/tmp/lex-old`).
- **0.9.3 (HEAD)** — current `claude/benchmark-lex-frame-ly1oE`.
  Built from `target/release/lex` (renamed to `lex-new`).

The four `lex` patches in flight that the maintainer expects to help
`lex-frame`:

| PR | Subject | Hot path in lex-frame it touches |
|---|---|---|
| `#405` | `list.cons` — `Vec` → `VecDeque` (`push_front` O(1)) | every `build_*_col` accumulator; `from_columns` fold; `group_by` per-group append; `provenance` cons; `range_list` recursion |
| `#407` | `Op::GetField` — monomorphic inline cache | every `df.columns` / `df.nrows` / `df.col_names` / `agg_spec.in_col` / `Col` variant payload access |
| `#409` | VM locals — stack-allocator arena | every function call (the bench is recursion-heavy; `range_list`, `build_int_loop`, `merge_sort` …) |
| `#413` | `Value::Str` → `SmolStr` SSO | the `g` group column (short string keys "0".."9") and CSV-style short tokens |

## Method

Each case is the same `lex` source compiled by the same compiler — only
the runtime differs. Wall time is measured around `lex run …` (includes
process start, parse, type-check, run); 3 runs per case, min / median /
max ms reported.

`--max-steps 100000000` is passed to both binaries because three of the
cases (`filter_rows`, `sort`, `group_by`) trip the default 10 M-step
guard on either runtime — that's a lex-frame algorithmic property (the
row API is linked-list indexed, so most ops are O(n²)), unaffected by
the runtime patches.

Driver: `bench/runbench.sh`. Bench source: `bench/bench.lex`.

```
$ ./bench/runbench.sh /home/user/lex-lang/target/release/lex-old 3
$ ./bench/runbench.sh /home/user/lex-lang/target/release/lex-new 3
```

## Results

Wall time in ms; median over 3 runs.

| case | 0.9.2 (baseline) | 0.9.3 (HEAD) | speed-up |
|---|---:|---:|---:|
| `build (n=200)`                  |    115 |     92 | **1.25×** |
| `build (n=1000)`                 |  1 609 |  1 118 | **1.44×** |
| `sum col (n=1000)`               |  1 636 |  1 143 | **1.43×** |
| `mean col (n=1000)`              |  1 614 |  1 157 | **1.39×** |
| `filter rows (n=300)`            | 25 744 | 17 867 | **1.44×** |
| `sort_by (n=500)`                |  2 249 |  1 896 | **1.19×** |
| `group_by + agg (n=1000, 10 grp)`| 11 354 |  8 092 | **1.40×** |

**Reading this.** Across seven cases the new runtime is **1.19–1.44×**
faster on `lex-frame` at the same workload, with no source change. The
biggest gains are on the allocation-and-traversal-heavy cases (`filter`,
`group_by`, `build`, `sum`) — exactly the paths PR #405 (`list.cons`)
and PR #409 (locals arena) target. Sort is the smallest win because
merge-sort spends most of its time in `merge_pairs` comparisons, where
the locals arena helps but `list.cons` is already off the hot path.

The `lex` process startup itself accounts for ~35-40 ms of every row
(parse + type-check of the bench file and its `src/*.lex` deps). The
`build (n=200)` row is dominated by that fixed cost; once you subtract
it, the steady-state speed-up on the heavier cases is closer to 1.5×.

## Result-correctness sanity check

Both binaries return identical results on every case:

| case | output |
|---|---|
| `bench_build 1000`  | `1000` |
| `bench_sum_x 1000`  | `500500` |
| `bench_mean_x 1000` | `1` (Some-was-returned flag) |
| `bench_filter 300`  | `150` |
| `bench_sort 500`    | `500` |
| `bench_groupby 1000`| `10` |

Plus `lex test` is green on `lex-frame` against the new runtime
(11 / 11 passed).

## Pandas scale reference (not a claim, just context)

For perspective on where an interpreted-VM dataframe library sits
relative to a mature columnar engine, the same operations on the same
sizes against pandas 3.0.3, measured by `bench/pandas_ref.py`
(median µs over 5 in-process runs, no subprocess overhead):

| case | pandas 3.0.3 | lex-frame on 0.9.3 |
|---|---:|---:|
| `build (n=1000)`                  |    0.7 ms |  1 118 ms |
| `sum col (n=1000)`                |    0.9 ms |  1 143 ms |
| `mean col (n=1000)`               |    0.9 ms |  1 157 ms |
| `sort_by (n=500)`                 |    0.8 ms |  1 896 ms |
| `group_by + agg (n=1000)`         |    5.1 ms |  8 092 ms |
| `filter rows (n=1000)*`           |    2.1 ms |  too slow (300-row run = 18 s) |

`*` pandas can run filter at n=1000 in 2 ms; `lex-frame`'s row-API is
linked-list-indexed (O(n²)), so it scales to n=300 here, not n=1000.

The 3-4 orders of magnitude gap is expected: pandas/Polars dispatch
each op as one C/Rust function call over a contiguous numeric buffer,
while `lex-frame` evaluates user-level Lex code against `List[Value]`
columns inside a tree-walking bytecode VM. `lex-frame`'s pitch is
agent-first ergonomics (immutability, typed errors, provenance,
LLM-shaped inspectors) — not raw throughput.

## "Is there an official benchmark for this kind of tool?"

Yes — for the dataframe space the de-facto standard is the **H2O.ai
db-benchmark**, originally published by H2O.ai and now maintained by
DuckDB Labs: <https://github.com/duckdblabs/db-benchmark> (with the
public dashboard at <https://duckdblabs.github.io/db-benchmark/>).
It's the suite pandas, Polars, DuckDB, data.table, Spark and Modin all
report against, and it covers `groupby` and `join` queries at 0.5 GB /
5 GB / 50 GB scales.

We are **not** running it here for two reasons:

1. The smallest db-benchmark dataset is 100 M rows (≈ 5 GB CSV).
   `lex-frame` at the current scaling — ~1 s per 1 000 rows for a
   column build — would need on the order of 30 hours per case before
   even getting to the operation under test. The micro-bench above
   captures the same *operation mix* (build, sum, mean, filter, sort,
   group-by-aggregate) at a size the VM can actually finish.

2. The db-benchmark dataset format (Parquet, multi-key joins, decimal
   types) is past what `lex-frame`'s `io` module supports today (CSV
   + JSON-rows only).

If `lex-frame` ever does want a db-benchmark row, the right path is:
add Parquet support, run the 0.5 GB `G1_1e7` group-by queries against
Polars / DuckDB / pandas at the same scale, and publish under the same
schema. Until then, this in-repo A/B is the honest comparison: same
source, same workload, just two builds of the runtime.

## Reproducing

```bash
# in /home/user/lex-lang
cargo build --release -p lex-cli                          # builds HEAD → lex-new
git worktree add /tmp/lex-old df2fc19~1                   # 0.9.2 sources
( cd /tmp/lex-old && CARGO_TARGET_DIR=/tmp/lex-old-target \
    cargo build --release -p lex-cli )                    # builds 0.9.2 → lex-old
cp /tmp/lex-old-target/release/lex target/release/lex-old
cp target/release/lex target/release/lex-new

# in /home/user/lex-frame
./bench/runbench.sh ~/lex-lang/target/release/lex-old 3
./bench/runbench.sh ~/lex-lang/target/release/lex-new 3
python3 bench/pandas_ref.py
```

## Path-1 slice-1 win — `agg.sum_col` vs `arrow.col_sum_int`

After lex-lang #428 landed `std.arrow` (Apache Arrow `RecordBatch` as a
first-class `Value` + native column kernels), the same `sum-a-column`
workload that today goes through `agg.sum_col` (which walks a
`List[Value]` in Lex bytecode) can be re-routed through one
`arrow_arith::aggregate::sum` call over a flat `i64` buffer. Same input,
same output, 48–63× less wall time:

| n | `bench_sum_x` (lex-frame `agg.sum_col`) | `arrow_sum_x` (Arrow kernel) | speed-up |
|---:|---:|---:|---:|
| 1 000 |    859 ms |  18 ms | **48×** |
| 5 000 | 20 143 ms | 320 ms | **63×** |

The Arrow kernel itself is essentially free — the
`arrow_sum_repeat (n=1000, k=100)` run takes the same wall time as
`(n=1000, k=1)`, so the build cost dominates. `arrow.read_csv` shipped
alongside the kernels in #428, so once rows arrive already-columnar
(via `bench_df.lex` / a future `frame.read_csv` wrapper), the ratio
compounds further. Reproduce locally (requires `lex` ≥ 0.9.4):

```bash
lex run --max-steps 1000000000 bench/bench.lex      bench_sum_x 1000
lex run --max-steps 1000000000 bench/bench_arrow.lex arrow_sum_x 1000
```

Once the lex-frame migration (lex-frame#6) ships, **every** lex-frame
column op gets this routing automatically — the public API stays the
same, only the engine underneath changes.

## Path-1 slice-2 win — pandas head-to-head via `std.df` (measured, lex 0.9.4)

Slice-1 above showed the Arrow kernel itself is essentially free.
Slice-2 measures the full end-to-end story: read a CSV, run one query
op, return the result size — apples-to-apples with the same workload
on pandas 3.0.3. Bench source: `bench/bench_df.lex`; pandas reference:
`bench/pandas_df_ref.py`.

Protocol: 7 invocations per cell, median ms reported, min/max in
parentheses; lex runs are fresh-process (`lex run …` per invocation —
includes parse, type-check, run); pandas runs are in-process after one
warmup. Both sides read the CSV fresh on every call, so the CSV-parse
cost is included on both sides. Machine: shared linux container, lex
0.9.4 release binary, pandas 3.0.3.

| op (read CSV + op) | n | lex 0.9.4 | pandas 3.0.3 | ratio |
|---|---:|---:|---:|---:|
| `group_by_csv`  | 100 k |  33 ms (32–34) |  36 ms (34–36) | within 8% |
| `sort_csv`      | 100 k |  36 ms (35–37) |  33 ms (33–35) | within 9% |
| `filter_gt_csv` | 100 k |  34 ms (32–35) |  29 ms (28–30) | pandas 17% faster |
| `sum_x_csv`     | 100 k |  28 ms (27–30) |  26 ms (26–27) | within 6% |
| `group_by_csv`  |   1 M | 215 ms (208–252) | 274 ms (269–281) | **lex 1.27× faster** |
| `sort_csv`      |   1 M | 257 ms (246–316) | 327 ms (316–386) | **lex 1.27× faster** |
| `filter_gt_csv` |   1 M | 226 ms (212–240) | 266 ms (261–273) | **lex 1.18× faster** |
| `sum_x_csv`     |   1 M | 180 ms (179–194) | 256 ms (252–260) | **lex 1.42× faster** |

**Reading this.** At 100 k rows the two are within 6–17% of each other —
lex's fresh-process startup (~25 ms parse + type-check, included in
every cell on the lex side) is a large fraction of the total at that
size, so the comparison is harsh on lex. At 1 M rows, where the query
itself dominates, **lex 0.9.4 beats pandas across all four ops** by
1.18–1.42×. Both sides are using Arrow-backed columnar storage; the
difference is that pandas pays a NumPy-block-manager round-trip for
group-by/sort, while `std.df` keeps the data in Polars throughout.

**Important caveat.** This is `arrow.read_csv` + `df.*` going through
`std.df` directly. The public `lex-frame` API (`frame.from_columns`,
`agg.sum_col`, `select.where`, etc.) **still routes through
`List[Value]`** as of this release, so this table is a Polars-via-lex
claim, not yet a lex-frame claim. The lex-frame wrapper migration is
tracked in lex-frame#6; once it lands, every public op inherits these
numbers automatically — same source, same agent-facing surface,
columnar engine underneath.

Reproduce locally (requires `lex` ≥ 0.9.4 and `pandas` ≥ 3.0):

```bash
# generate CSVs
python3 -c "
import csv
for n,p in [(100_000,'/tmp/bench.csv'),(1_000_000,'/tmp/bench_1m.csv')]:
    with open(p,'w') as f:
        w=csv.writer(f); w.writerow(['x','y','g'])
        for i in range(1,n+1): w.writerow([i,i,str(i%10)])"

# lex side (fresh process each run)
lex run --allow-effects fs_read bench/bench_df.lex group_by_csv  '"/tmp/bench_1m.csv"'
lex run --allow-effects fs_read bench/bench_df.lex sort_csv      '"/tmp/bench_1m.csv"'
lex run --allow-effects fs_read bench/bench_df.lex filter_gt_csv '"/tmp/bench_1m.csv"' 500000
lex run --allow-effects fs_read bench/bench_df.lex sum_x_csv     '"/tmp/bench_1m.csv"'

# pandas side
python3 bench/pandas_df_ref.py
```

## Path-1 slice-3/4 win — the PUBLIC lex-frame API on std.df (measured, lex 0.10.7)

Slice-2 above was a std.df-direct claim. As of this slice the public
lex-frame surface itself routes through std.df when the frame is
arrow-backed: `select.filter_*_fast`, `sort.sort_by_fast`,
`group.group_agg_fast`, `join.*_join_fast`, `io.write_csv_fast`, plus
Parquet I/O (`io.read_parquet` / `write_parquet`). Bench source:
`bench/bench_frame_fast.lex` — the same four ops as `bench_df.lex`,
called through `io.read_csv_fast` + the `_fast` wrappers (provenance
recording, FrameError mapping, DataFrame record round-trip included).

Protocol: 7 fresh-process invocations per cell, median ms (lex side
includes parse + type-check of lex-frame's 13 modules on every run);
pandas 3.0.5 in-process after one warmup, 5-run median. Same shared
linux container for all three columns; CSVs per the slice-2 recipe.

| op (read CSV + op) | n | lex-frame fast API | std.df direct | pandas 3.0.5 |
|---|---:|---:|---:|---:|
| `group_by_csv`  | 100 k |  64 ms |  31 ms |  30 ms |
| `sort_csv`      | 100 k |  65 ms |  32 ms |  25 ms |
| `filter_gt_csv` | 100 k |  56 ms |  24 ms |  22 ms |
| `sum_x_csv`     | 100 k |  50 ms |  18 ms |  22 ms |
| `group_by_csv`  |   1 M | 205 ms | 156 ms | 198 ms |
| `sort_csv`      |   1 M | 229 ms | 185 ms | 222 ms |
| `filter_gt_csv` |   1 M | 192 ms | 161 ms | 178 ms |
| `sum_x_csv`     |   1 M | 153 ms | 114 ms | 164 ms |
| `pipeline_csv` (filter → sort → group) | 1 M | 229 ms | — | — |

**Reading this.** At 1 M rows the public lex-frame API is within
±10-15% of pandas on every op (faster on `sum`, slightly slower on the
rest) — versus **3-4 orders of magnitude slower** on the legacy
List[Value] engine (the slice-0 table above: `filter` needed 18 s for
300 rows; it now does 500 000 rows in 192 ms, startup included). The
gap between the `lex-frame fast API` and `std.df direct` columns is
almost entirely the fixed per-process parse + type-check of the
lex-frame module tree (~30-40 ms) — the wrapper cost per op
(provenance cons + FrameError mapping) is ~1-2 ms, and `pipeline_csv`
(three chained ops) costs the same as its slowest single op.

The remaining legacy-only surface: closure predicates
(`select.filter_rows`), `std`/`var`/`count_non_null` group aggs, bool
and nullable column construction, and the inspect walkers. Everything
else can stay arrow-backed end-to-end.

Reproduce:

```bash
# CSVs per the slice-2 recipe, then:
lex run --allow-effects fs_read,fs_write,io bench/bench_frame_fast.lex group_by_csv  '"/tmp/bench_1m.csv"'
lex run --allow-effects fs_read,fs_write,io bench/bench_frame_fast.lex sort_csv      '"/tmp/bench_1m.csv"'
lex run --allow-effects fs_read,fs_write,io bench/bench_frame_fast.lex filter_gt_csv '"/tmp/bench_1m.csv"' 500000
lex run --allow-effects fs_read,fs_write,io bench/bench_frame_fast.lex sum_x_csv     '"/tmp/bench_1m.csv"'
lex run --allow-effects fs_read,fs_write,io bench/bench_frame_fast.lex pipeline_csv  '"/tmp/bench_1m.csv"' 500000
python3 bench/pandas_df_ref.py
```

(The `io` grant is needed because the program imports `src/io`, whose
legacy readers carry `[io]`; the fast ops themselves only exercise
`fs_read`.)

## H2O db-benchmark groupby (G1 schema, 1e6) — first showing (lex 0.10.7)

Issue #6's acceptance criteria asked for lex-frame to show up on a
recognised public benchmark once the columnar path could carry it.
With multi-key `group_agg_by_keys_fast` landed, the official
db-benchmark groupby queries q1-q5 now run through the public
lex-frame API: `bench/h2o_groupby.lex`, dataset from
`bench/gen_h2o_csv.py` (official G1 schema and cardinalities, K=100,
seed 42). 1e6 rows / 49 MB CSV; 5-run medians; lex fresh-process,
pandas/polars in-process after warmup (protocol harsh on lex).

| query | groups | lex-frame fast API | pandas 3.0.5 | Polars 1.43 |
|---|---:|---:|---:|---:|
| q1: sum v1 by id1 | 100 | 800 ms | 761 ms | 69 ms |
| q2: sum v1 by id1,id2 | 10 000 | 515 ms | 880 ms | 154 ms |
| q3: sum v1, mean v3 by id3 | 10 000 | 539 ms | 809 ms | 81 ms |
| q4: mean v1,v2,v3 by id4 | 100 | 484 ms | 716 ms | 64 ms |
| q5: sum v1,v2,v3 by id6 | 10 000 | 512 ms | 741 ms | 80 ms |

**Reading this.** lex-frame is at or ahead of pandas on 4 of 5
queries — on the benchmark suite pandas itself reports against.
Native Polars is ~7-10x ahead of both; nearly all of that gap on the
lex side is `arrow.read_csv` (single-threaded arrow-rs reader,
~400-450 ms of every cell on this string-heavy file) versus Polars'
parallel CSV reader. The group-by kernel itself IS Polars in both
columns. Routing `arrow.read_csv` through the Polars reader upstream
(lex-lang) would close most of the distance; Parquet input closes it
today (`sum_x` at 1M: 153 ms via CSV, 35 ms via `read_parquet`).

Not yet runnable from the official suite: q6 (median — no kernel),
q7's derived `max-min` column (the group halves run, see
`q7_partial`), q8-q10 (window/regression/6-key-count kernels).

```bash
python3 bench/gen_h2o_csv.py 1000000 /tmp/h2o_g1_1e6.csv
lex run --allow-effects fs_read,fs_write,io bench/h2o_groupby.lex q2 '"/tmp/h2o_g1_1e6.csv"'
```

## Lazy plans — plan rewrites vs the eager fast API (measured, lex 0.10.7)

`lazy.collect` runs the same std.df kernels as the eager `_fast` ops;
the delta below is purely what the plan-level rewrites buy (filter
hoisting + projection pruning — lex-frame#16/#17). Interleaved A/B
(eager/lazy alternating per iteration so load drift cancels), 9
samples, median wall time, fresh `lex run` process per sample, n=1e6:

| workload | eager | lazy | note |
|---|---:|---:|---|
| filter→sort→group pipeline (CSV x,y,g) | 280 ms | 231 ms | prunes `y` before the sort |
| H2O q2 (CSV, 9 cols) | 527 ms | 496 ms | CSV reader can't prune; post-read projection only |
| H2O q2 (parquet, 9 cols) | 323 ms | **177 ms** | projection pushed into the parquet reader — 3 of 9 columns decoded |

**Reading this.** Projection pushdown into the parquet reader is the
headline: q2 drops 45% with zero kernel changes. On CSV the reader
decodes every column regardless (upstream `arrow.read_csv` has no
projection parameter yet — lex-lang candidate once measurement
justifies it), so lazy only helps CSV pipelines whose intermediate
ops carry pruned columns (the pipeline row). These numbers are on
lex 0.10.7's single-threaded CSV reader; the 0.10.8 parallel reader
shrinks every CSV cell further and is orthogonal to these rewrites.

```bash
python3 bench/gen_h2o_csv.py 1000000 /tmp/h2o_g1_1e6.csv
lex run --allow-effects fs_read,fs_write,io bench/bench_lazy.lex prep_parquet '"/tmp/h2o_g1_1e6.csv"' '"/tmp/h2o_g1_1e6.parquet"'
lex run --allow-effects fs_read,fs_write,io bench/bench_lazy.lex q2_parquet_lazy '"/tmp/h2o_g1_1e6.parquet"'
```
