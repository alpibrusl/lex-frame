"""
Reference timings for the same operations against pandas, at the same sizes
the lex-frame benchmark runs. This is *scale context only* — pandas is a
mature C-backed columnar engine and is expected to be far faster than an
interpreted Lex VM. The point is to know the order of magnitude.

Each op is timed once after a single warmup; the printed number is the
median of 5 runs (microseconds).
"""

import statistics
import time

import pandas as pd


def make_df(n: int) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "x": list(range(1, n + 1)),
            "y": list(range(1, n + 1)),
            "g": [str(i % 10) for i in range(1, n + 1)],
        }
    )


def time_us(fn, runs: int = 5) -> float:
    fn()  # warmup
    samples = []
    for _ in range(runs):
        t0 = time.perf_counter_ns()
        fn()
        samples.append((time.perf_counter_ns() - t0) / 1_000)
    return statistics.median(samples)


def main() -> None:
    cases = [
        ("build (n=200)",          lambda: make_df(200)),
        ("build (n=1000)",         lambda: make_df(1000)),
        ("sum col (n=1000)",       lambda: make_df(1000)["x"].sum()),
        ("mean col (n=1000)",      lambda: make_df(1000)["x"].mean()),
        ("filter rows (n=1000)",   lambda: make_df(1000).query("x % 2 == 0")),
        ("sort_by (n=500)",        lambda: make_df(500).sort_values("x")),
        ("group_by+agg (n=1000, 10 grp)",
            lambda: make_df(1000).groupby("g").agg(sum_x=("x", "sum"),
                                                   mean_y=("y", "mean"))),
    ]

    print(f"{'case':40s} {'median us':>12s}")
    print(f"{'-' * 40} {'-' * 12}")
    for label, fn in cases:
        us = time_us(fn)
        print(f"{label:40s} {us:>12.1f}")


if __name__ == "__main__":
    main()
