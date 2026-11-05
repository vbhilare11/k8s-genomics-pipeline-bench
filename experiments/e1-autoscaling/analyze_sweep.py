#!/usr/bin/env python3
"""Gap sweep: replica-seconds and p95 wait vs idle gap, per mode, from the
summary.csv files of E1b (240 s) and E1c-g480 / E1c-g900."""
import csv
import os
import statistics
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results")
EXPS = ["E1b", "E1c-g480", "E1c-g900"]


def main():
    rows = []
    for exp in EXPS:
        path = os.path.join(RESULTS, exp, "summary.csv")
        if not os.path.exists(path):
            print(f"missing {path}", file=sys.stderr)
            continue
        rows += list(csv.DictReader(open(path)))
    agg = {}
    for r in rows:
        key = (r["mode"], int(r["gap_s"]))
        agg.setdefault(key, {"replica_seconds": [], "wait_p95_s": [], "makespan_s": []})
        for k in agg[key]:
            agg[key][k].append(float(r[k]))
    modes = sorted({m for m, _ in agg})
    gaps = sorted({g for _, g in agg})

    out_csv = os.path.join(RESULTS, "e1_gap_sweep.csv")
    with open(out_csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["mode", "gap_s", "n", "replica_seconds_med", "wait_p95_med", "makespan_med"])
        for m in modes:
            for g in gaps:
                a = agg.get((m, g))
                if a:
                    w.writerow([m, g, len(a["replica_seconds"]),
                                statistics.median(a["replica_seconds"]),
                                round(statistics.median(a["wait_p95_s"]), 1),
                                round(statistics.median(a["makespan_s"]), 1)])
    print(open(out_csv).read())

    figdir = os.path.join(RESULTS, "figures")
    os.makedirs(figdir, exist_ok=True)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9, 3.4))
    for m in modes:
        xs = [g for g in gaps if (m, g) in agg]
        ax1.plot(xs, [statistics.median(agg[(m, g)]["replica_seconds"]) for g in xs], marker="o", label=m)
        ax2.plot(xs, [statistics.median(agg[(m, g)]["wait_p95_s"]) for g in xs], marker="o", label=m)
    ax1.set_xlabel("idle gap between bursts (s)"); ax1.set_ylabel("replica-seconds (median)")
    ax2.set_xlabel("idle gap between bursts (s)"); ax2.set_ylabel("queue wait p95 (s, median)")
    for ax in (ax1, ax2):
        ax.set_xticks(gaps); ax.grid(alpha=0.3)
    ax1.legend()
    fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(os.path.join(figdir, f"e1_gap_sweep.{ext}"), dpi=150)
    print(f"wrote {figdir}/e1_gap_sweep.png|pdf")
    return 0


if __name__ == "__main__":
    sys.exit(main())
