#!/usr/bin/env python3
"""Regenerate paper figures from results/*/summary.csv.  Usage: ./paper/figures.py"""
import csv
import statistics
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "results"
OUT = ROOT / "paper" / "figures"
OUT.mkdir(parents=True, exist_ok=True)


def rows(exp):
    p = RES / exp / "summary.csv"
    if not p.exists():
        print(f"skip {exp}: no summary.csv")
        return []
    with p.open() as f:
        return list(csv.DictReader(f))


def fnum(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def stat(rs, key, fn=statistics.median):
    vals = [fnum(r.get(key)) for r in rs]
    vals = [v for v in vals if v is not None]
    return fn(vals) if vals else None


def save(fig, name):
    for ext in ("pdf", "png"):
        fig.savefig(OUT / f"{name}.{ext}", bbox_inches="tight", dpi=200)
    plt.close(fig)
    print("wrote", name)


def fig_startup():
    delays = [0, 10, 30]
    fig, ax = plt.subplots(figsize=(4.2, 3))
    for m, label in ((0, "minReplicas 0"), (1, "minReplicas 1")):
        ys = [stat(rows(f"E1d-s{d}-m{m}"), "wait_p95_s") for d in delays]
        if any(y is None for y in ys):
            continue
        ax.plot(delays, ys, marker="o", label=label)
    ax.set_xlabel("simulated pod startup delay (s)")
    ax.set_ylabel("queue wait p95 (s)")
    ax.set_xticks(delays)
    ax.legend()
    ax.grid(alpha=0.3)
    save(fig, "e1d_startup")


def fig_cooldown():
    cds = [60, 180, 300]
    rs = {cd: rows(f"E1d-g900-cd{cd}") for cd in cds}
    cost = [stat(rs[cd], "replica_seconds", statistics.mean) for cd in cds]
    p95 = [stat(rs[cd], "wait_p95_s", statistics.mean) for cd in cds]
    if any(v is None for v in cost + p95):
        return
    fig, (a, b) = plt.subplots(1, 2, figsize=(7, 3))
    a.plot(cds, cost, marker="o")
    a.set_xlabel("KEDA cooldownPeriod (s)")
    a.set_ylabel("replica-seconds (mean of 2)")
    a.grid(alpha=0.3)
    b.plot(cds, p95, marker="o")
    b.set_xlabel("KEDA cooldownPeriod (s)")
    b.set_ylabel("queue wait p95 (s)")
    b.set_ylim(0, max(p95) * 1.3)
    b.grid(alpha=0.3)
    for ax in (a, b):
        ax.set_xticks(cds)
    save(fig, "e1d_cooldown")


def fig_delivery():
    groups = [("E2", "direct", "100 %\ndirect"), ("E2", "canary", "100 %\ncanary"),
              ("E2b", "direct", "30 %\ndirect"), ("E2b", "canary", "30 %\ncanary"),
              ("E2c", "canary-abs", "30 %\ncanary-abs")]
    fig, (a, b) = plt.subplots(1, 2, figsize=(8, 3.2))
    labels = []
    for i, (exp, mode, label) in enumerate(groups):
        rs = [r for r in rows(exp) if r.get("mode") == mode and r.get("release") == "bad"]
        if not rs:
            continue
        labels.append((i, label))
        lost = [fnum(r.get("jobs_failed")) for r in rs]
        rec = [fnum(r.get("recovery_s")) for r in rs]
        a.scatter([i] * len(lost), lost, alpha=0.7)
        caught = [v for v in rec if v is not None]
        b.scatter([i] * len(caught), caught, alpha=0.7)
        missed = sum(1 for v in rec if v is None)
        if missed:
            b.annotate(f"{missed} promoted", (i, 0), textcoords="offset points",
                       xytext=(0, -18), ha="center", fontsize=8, color="crimson")
    for ax in (a, b):
        ax.set_xticks([i for i, _ in labels])
        ax.set_xticklabels([lab for _, lab in labels], fontsize=8)
        ax.grid(alpha=0.3, axis="y")
    a.set_ylabel("jobs failed per release")
    b.set_ylabel("time to rollback (s)")
    b.set_ylim(bottom=0)
    save(fig, "e2_delivery")


def fig_drift():
    pairs = [("E1c-g900", "Nov 5 (0.1.1)"), ("E1c-drift-check", "Nov 18 (0.2.2)")]
    fig, ax = plt.subplots(figsize=(4.2, 3))
    width = 0.35
    for j, mode in enumerate(("fixed", "keda-inflight")):
        ys = [stat([r for r in rows(exp) if r.get("mode") == mode], "replica_seconds")
              for exp, _ in pairs]
        if any(y is None for y in ys):
            continue
        ax.bar([i + (j - 0.5) * width for i in range(len(pairs))], ys, width, label=mode)
    ax.set_xticks(range(len(pairs)))
    ax.set_xticklabels([lab for _, lab in pairs])
    ax.set_ylabel("replica-seconds (900 s gaps)")
    ax.legend()
    ax.grid(alpha=0.3, axis="y")
    save(fig, "e1c_drift")


if __name__ == "__main__":
    fig_startup()
    fig_cooldown()
    fig_delivery()
    fig_drift()
