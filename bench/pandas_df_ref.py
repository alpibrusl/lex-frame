"""Pandas reference for the std.arrow + std.df benchmark.

Times the same workload `bench/bench_df.lex` runs: read a CSV, run one
query op, return the row count. Reported as median ms over 5 runs after
one warmup. Matches the lex bench's apples-to-apples accounting: each
op reads the CSV fresh (no cached DataFrame) so cell-by-cell comparison
to lex's `lex run` wall time is fair.

Generate the CSVs:

    python3 -c "
    import csv
    for n, p in [(100_000, '/tmp/bench.csv'), (1_000_000, '/tmp/bench_1m.csv')]:
        with open(p, 'w') as f:
            w = csv.writer(f); w.writerow(['x','y','g'])
            for i in range(1, n+1): w.writerow([i, i, str(i%10)])
    "
"""
import statistics
import time

import pandas as pd


def time_ms(fn, runs: int = 5) -> float:
    fn()  # warmup
    samples = []
    for _ in range(runs):
        t0 = time.perf_counter_ns()
        fn()
        samples.append((time.perf_counter_ns() - t0) / 1_000_000)
    return statistics.median(samples)


def main() -> None:
    for n, path in [(100_000, "/tmp/bench.csv"), (1_000_000, "/tmp/bench_1m.csv")]:
        print(f"n={n}:")

        def group_by_csv() -> int:
            df = pd.read_csv(path)
            return len(df.groupby("g").agg(sum_x=("x", "sum"), mean_y=("y", "mean")))

        def sort_csv() -> int:
            df = pd.read_csv(path)
            return len(df.sort_values("x", ascending=False))

        def filter_gt_csv() -> int:
            df = pd.read_csv(path)
            return len(df[df["x"] > n // 2])

        def sum_x_csv() -> int:
            df = pd.read_csv(path)
            return int(df["x"].sum())

        print(f"  group_by_csv    {time_ms(group_by_csv):7.1f} ms")
        print(f"  sort_csv        {time_ms(sort_csv):7.1f} ms")
        print(f"  filter_gt_csv   {time_ms(filter_gt_csv):7.1f} ms")
        print(f"  sum_x_csv       {time_ms(sum_x_csv):7.1f} ms")


if __name__ == "__main__":
    main()
