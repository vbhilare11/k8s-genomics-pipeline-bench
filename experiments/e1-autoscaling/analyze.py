#!/usr/bin/env python3
"""Summarise E1 runs under results/E1 into summary.csv and figures/.

Metrics per run: makespan, queue-wait p50/p95, job-duration median, time to first
scale-up, replica-seconds (integral of ready replicas over the run), and
jobs-per-replica-minute (throughput per unit of capacity).
"""
import csv
import glob
import json
import os
import statistics
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

EXP = sys.argv[1] if len(sys.argv) > 1 else "E1"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results", EXP)


def pct(values, p):
    if not values:
        return float("nan")
    s = sorted(values)
    k = (len(s) - 1) * p
    f, c = int(k), min(int(k) + 1, len(s) - 1)
    return s[f] + (s[c] - s[f]) * (k - f)


def load_run(path):
    with open(os.path.join(path, "meta.json")) as fh:
        meta = json.load(fh)
    results = [json.loads(l) for l in open(os.path.join(path, "results.jsonl")) if l.strip()]
    timeline = list(csv.DictReader(open(os.path.join(path, "timeline.csv"))))
    return meta, results, timeline


def analyse(meta, results, timeline):
    waits = [r["started_at"] - r["submitted_at"] for r in results if r.get("submitted_at")]
    durs = [r["duration_s"] for r in results]
    start = meta["start_ts"]
    base = int(timeline[0]["ready_replicas"]) if timeline else 0
    first_up = next((float(t["ts"]) - start for t in timeline if int(t["ready_replicas"]) > base), None)
    rep_s = 0.0
    for a, b in zip(timeline, timeline[1:]):
        rep_s += int(a["ready_replicas"]) * (float(b["ts"]) - float(a["ts"]))
    return {
        "mode": meta["mode"], "replicate": meta["replicate"], "jobs": meta["jobs"],
        "bursts": meta.get("bursts", 1), "gap_s": meta.get("gap_s", 0),
        "completed": meta["completed"], "makespan_s": round(meta["makespan_s"], 1),
        "wait_p50_s": round(pct(waits, 0.5), 1), "wait_p95_s": round(pct(waits, 0.95), 1),
        "job_median_s": round(statistics.median(durs), 1) if durs else float("nan"),
        "first_scaleup_s": round(first_up, 1) if first_up is not None else "",
        "replica_seconds": round(rep_s, 0),
        "jobs_per_replica_min": round(meta["completed"] / (rep_s / 60), 3) if rep_s else "",
        "git_sha": meta["git_sha"][:10],
    }


def main():
    runs = sorted(p for p in glob.glob(os.path.join(ROOT, "*-n*-r*"))
                  if os.path.exists(os.path.join(p, "meta.json")))
    if not runs:
        print("no runs found", file=sys.stderr)
        return 1
    rows, series = [], {}
    for path in runs:
        meta, results, timeline = load_run(path)
        rows.append(analyse(meta, results, timeline))
        series.setdefault(meta["mode"], []).append((meta, timeline, results))

    fields = list(rows[0].keys())
    with open(os.path.join(ROOT, "summary.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    for r in rows:
        print("  ".join(f"{k}={r[k]}" for k in fields))

    figdir = os.path.join(ROOT, "figures")
    os.makedirs(figdir, exist_ok=True)

    # Fig 1: replicas and queue length over time, replicate 1 of each mode
    fig, axes = plt.subplots(len(series), 1, figsize=(8, 2.6 * len(series)), sharex=True)
    axes = [axes] if len(series) == 1 else list(axes)
    for ax, mode in zip(axes, sorted(series)):
        meta, tl, _ = series[mode][0]
        t = [float(x["ts"]) - meta["start_ts"] for x in tl]
        ax.step(t, [int(x["ready_replicas"]) for x in tl], where="post", label="ready replicas")
        ax2 = ax.twinx()
        ax2.plot(t, [int(x["queue_len"]) for x in tl], color="tab:orange", alpha=0.7, label="queue length")
        ax.set_ylabel("replicas"); ax2.set_ylabel("queued jobs"); ax.set_title(mode)
        ax.set_ylim(0, 3.5); ax.grid(alpha=0.3)
    axes[-1].set_xlabel("seconds since submission")
    fig.tight_layout(); fig.savefig(os.path.join(figdir, "e1_timeline.png"), dpi=150); plt.close(fig)

    # Fig 2: queue wait distribution per mode (all replicates pooled)
    fig, ax = plt.subplots(figsize=(6, 3.5))
    modes = sorted(series)
    data = [[r["started_at"] - r["submitted_at"] for _, _, res in series[m] for r in res] for m in modes]
    ax.boxplot(data, tick_labels=modes, showfliers=False)
    ax.set_ylabel("queue wait (s)"); ax.grid(alpha=0.3)
    fig.tight_layout(); fig.savefig(os.path.join(figdir, "e1_queue_wait.png"), dpi=150); plt.close(fig)

    # Fig 3: makespan vs replica-seconds (cost/latency trade-off)
    fig, ax = plt.subplots(figsize=(5.5, 3.5))
    for m in modes:
        xs = [r["replica_seconds"] for r in rows if r["mode"] == m]
        ys = [r["makespan_s"] for r in rows if r["mode"] == m]
        ax.scatter(xs, ys, label=m, s=50)
    ax.set_xlabel("replica-seconds consumed"); ax.set_ylabel("makespan (s)"); ax.legend(); ax.grid(alpha=0.3)
    fig.tight_layout(); fig.savefig(os.path.join(figdir, "e1_tradeoff.png"), dpi=150); plt.close(fig)
    print(f"wrote {os.path.join(ROOT, 'summary.csv')} and {figdir}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
