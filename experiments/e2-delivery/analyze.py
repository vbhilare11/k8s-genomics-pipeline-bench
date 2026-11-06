#!/usr/bin/env python3
"""Summarise E2 runs: jobs failed per release, exposure window of the bad
version, time to recovery, and (good releases) time to full promotion."""
import csv
import glob
import json
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

EXP = sys.argv[1] if len(sys.argv) > 1 else "E2"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results", EXP)


def load(path):
    meta = json.load(open(os.path.join(path, "meta.json")))
    res = [json.loads(l) for l in open(os.path.join(path, "results.jsonl")) if l.strip()]
    tl = list(csv.DictReader(open(os.path.join(path, "timeline.csv"))))
    return meta, res, tl


def analyse(meta, res, tl):
    t0 = meta["t_release"]
    errs = sorted(r["finished_at"] for r in res if r["status"] == "error")
    oks = [r for r in res if r["status"] == "ok"]
    row = {
        "mode": meta["mode"], "release": meta["release"], "replicate": meta["replicate"],
        "jobs_total": len(res), "jobs_ok": len(oks), "jobs_failed": len(errs),
        "first_fail_s": round(errs[0] - t0, 1) if errs else "",
        "last_fail_s": round(errs[-1] - t0, 1) if errs else "",
        "exposure_s": round(errs[-1] - errs[0], 1) if len(errs) > 1 else (0.0 if errs else ""),
        "recovery_s": "", "promotion_s": "",
    }
    if meta["mode"] == "direct":
        if meta.get("t_undo"):
            row["recovery_s"] = round(meta["t_undo"] - t0, 1)
        if meta["release"] == "good":
            # rollout complete when the live image equals the good image and target ready == replicas
            done = next((float(x["ts"]) for x in tl if float(x["ts"]) > t0
                         and int(x["ready_target"] or 0) >= meta["replicas"]), None)
            row["promotion_s"] = round(done - t0, 1) if done else ""
    else:
        phases = [(float(x["ts"]), x["canary_phase"]) for x in tl if float(x["ts"]) > t0]
        failed = next((ts for ts, p in phases if p == "Failed"), None)
        succ = next((ts for ts, p in phases if p == "Succeeded"), None)
        if meta["release"] == "bad" and failed:
            row["recovery_s"] = round(failed - t0, 1)
        if meta["release"] == "good" and succ:
            row["promotion_s"] = round(succ - t0, 1)
    row["git_sha"] = meta["git_sha"][:10]
    return row


def main():
    runs = sorted(p for p in glob.glob(os.path.join(ROOT, "*-r*")) if os.path.exists(os.path.join(p, "meta.json")))
    if not runs:
        print("no runs", file=sys.stderr); return 1
    rows = [analyse(*load(p)) for p in runs]
    fields = list(rows[0].keys())
    with open(os.path.join(ROOT, "summary.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields); w.writeheader(); w.writerows(rows)
    for r in rows:
        print("  ".join(f"{k}={r[k]}" for k in fields))

    figdir = os.path.join(ROOT, "figures"); os.makedirs(figdir, exist_ok=True)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9, 3.4))
    for ax, key, title in ((ax1, "jobs_failed", "jobs failed per bad release"),
                           (ax2, "recovery_s", "time to rollback (s)")):
        data = {m: [r[key] for r in rows if r["mode"] == m and r["release"] == "bad" and r[key] != ""]
                for m in ("direct", "canary")}
        ax.boxplot([data["direct"], data["canary"]], tick_labels=["direct", "canary"])
        ax.set_title(title); ax.grid(alpha=0.3)
    fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(os.path.join(figdir, f"e2_bad_release.{ext}"), dpi=150)
    print(f"wrote {os.path.join(ROOT, 'summary.csv')} and {figdir}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
