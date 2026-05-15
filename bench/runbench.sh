#!/usr/bin/env bash
# Usage: ./bench/runbench.sh <lex-binary> [N_RUNS]
# Prints min / median / max wall-clock ms across N_RUNS for each case.
# Wall time includes process start, parse, type-check and run — the way
# an agent would actually invoke `lex run` from a tool harness.
set -euo pipefail
LEX=${1:?lex binary path required}
N_RUNS=${2:-3}

# filter / sort / groupby are O(n^2) inside lex-frame itself
# (list-indexed row access), so we size them down to keep one run
# under 30s on the old binary. The sizes are identical across
# binaries, so the A/B comparison is apples-to-apples.
CASES=(
  "bench_build:200:build (n=200)"
  "bench_build:1000:build (n=1000)"
  "bench_sum_x:1000:sum col (n=1000)"
  "bench_mean_x:1000:mean col (n=1000)"
  "bench_filter:300:filter rows (n=300)"
  "bench_sort:500:sort_by (n=500)"
  "bench_groupby:1000:group_by+agg (n=1000, 10 grp)"
)

printf '%-40s %10s %10s %10s\n' "case" "min ms" "med ms" "max ms"
printf '%-40s %10s %10s %10s\n' "----" "------" "------" "------"

for c in "${CASES[@]}"; do
  IFS=':' read -r fn arg label <<<"$c"
  times=()
  for r in $(seq 1 $N_RUNS); do
    t1=$(date +%s%3N)
    "$LEX" run --max-steps 100000000 bench/bench.lex "$fn" "$arg" >/dev/null 2>&1 || true
    t2=$(date +%s%3N)
    times+=("$((t2 - t1))")
  done
  sorted=$(printf '%s\n' "${times[@]}" | sort -n)
  mn=$(echo "$sorted" | head -1)
  mid=$(( (N_RUNS + 1) / 2 ))
  md=$(echo "$sorted" | sed -n "${mid}p")
  mx=$(echo "$sorted" | tail -1)
  printf '%-40s %10s %10s %10s\n' "$label" "$mn" "$md" "$mx"
done
