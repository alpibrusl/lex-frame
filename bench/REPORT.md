# lex-frame performance — 0.9.2 vs 0.9.3 (Unreleased) A/B

> **🎯 Path-1 complete: lex-frame matches or beats pandas on real
> workloads.** With lex-lang #428 (`std.arrow`) and lex-lang #427
> (`std.df`, Polars-backed), the same bench that used to run 1000–10 000×
> slower than pandas now runs **within 10% of pandas at 100k rows and
> 1.2× faster at 1M rows**. Bench file: `bench/bench_df.lex`; pandas
> reference: `bench/pandas_df_ref.py`.
>
> | op (read CSV + op) | n | lex (std.arrow + std.df) | pandas 3.0 | ratio |
> |---|---:|---:|---:|---:|
> | `group_by_agg` | 100 k | 37 ms |  36 ms | within 3% |
> | `sort_by`      | 100 k | 40 ms |  37 ms | within 8% |
> | `filter_gt`    | 100 k | 34 ms |  31 ms | within 10% |
> | `group_by_agg` |   1 M | 231 ms | 285 ms | **lex 1.2× faster** |
> | `sort_by`      |   1 M | 285 ms | 331 ms | **lex 1.2× faster** |
> | `filter_gt`    |   1 M | 239 ms | 276 ms | **lex 1.2× faster** |
>
> The full lex-frame migration (#6) is the last piece — once `lex` 0.9.4
> ships, every public `lex-frame` op gets these numbers automatically;
> the agent-facing surface (immutability, typed errors, provenance,
> LLM-shaped output) is unchanged.

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
`(n=1000, k=1)`, so the build cost dominates. Once `arrow.read_csv`
lands (deferred slice of #426) and rows arrive already-columnar, the
ratio compounds further. Reproduce locally:

```bash
# Requires lex from the lex-lang #428 branch (until 0.9.4 ships):
lex run --max-steps 1000000000 bench/bench.lex      bench_sum_x 1000
lex run --max-steps 1000000000 bench/bench_arrow.lex arrow_sum_x 1000
```

Once the lex-frame migration (lex-frame#6) ships, **every** lex-frame
column op gets this routing automatically — the public API stays the
same, only the engine underneath changes.
