"""Generate a db-benchmark-style G1 group-by dataset.

Schema and cardinalities follow the H2O.ai db-benchmark groupby table
(https://github.com/duckdblabs/db-benchmark): K=100 low-cardinality
groups for id1/id2 (str) and id4/id5 (int), N/K high-cardinality
groups for id3 (str) and id6 (int), int measures v1 (1..5) and
v2 (1..15), float measure v3. Deterministic seed so runs compare.

    python3 bench/gen_h2o_csv.py 1000000 /tmp/h2o_g1_1e6.csv
"""
import csv
import random
import sys

n = int(sys.argv[1]) if len(sys.argv) > 1 else 1_000_000
path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/h2o_g1_1e6.csv"
K = 100
nk = max(n // K, 1)

rng = random.Random(42)
with open(path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id1", "id2", "id3", "id4", "id5", "id6", "v1", "v2", "v3"])
    for _ in range(n):
        w.writerow([
            f"id{rng.randint(1, K):03d}",
            f"id{rng.randint(1, K):03d}",
            f"id{rng.randint(1, nk):010d}",
            rng.randint(1, K),
            rng.randint(1, K),
            rng.randint(1, nk),
            rng.randint(1, 5),
            rng.randint(1, 15),
            round(rng.uniform(0, 100), 6),
        ])
print(f"wrote {n} rows to {path}")
