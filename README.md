# k8s-genomics-pipeline-bench

A reproducible benchmark for operating clinical-style genomic (NGS) pipelines on Kubernetes:
event-driven autoscaling (KEDA vs. HPA) and progressive delivery (canary vs. direct rollout)
measured under controlled, synthetic load using public 1000 Genomes data.

**Status:** all planned experiments for the first paper are complete (tag `v0.3.0`).
Manuscript in preparation; raw results for every run are in `results/`.

## Why

Genomic analysis pipelines are bursty, compute-heavy batch workloads with clinical
turnaround-time requirements. This project measures how common Kubernetes scaling and
delivery mechanisms behave for such workloads, so that hospitals, labs and platform teams
can make evidence-based choices rather than guesses.

## Experiments

Every E1 run is 24 jobs in 3 bursts of 8; each job runs fastp → bwa mem (GRCh38 chr20) →
samtools on 200k reads (~70 s). Each `results/<EXP>/<run>/` holds `meta.json`,
`timeline.csv`, `results.jsonl`, `deployment.yaml`, `versions.lock`.

| Experiment | Question | Varied | Image |
| --- | --- | --- | --- |
| `E1` | Single 30-job burst, 4 scaling modes | mode | 0.1.x |
| `E1b` | Bursty arrivals, 240 s gaps | mode (fixed, hpa, keda, keda-inflight) | 0.1.x |
| `E1c-g480`, `E1c-g900` | Does idle gap change the ranking? | gap | 0.1.1 |
| `E1d-s{0,10,30}-m{0,1}` | Cold-start cost; does a warm standby help? | startup delay × minReplicas | 0.2.2 |
| `E1d-g900-cd{60,180,300}` | What does KEDA cooldown cost? | cooldownPeriod | 0.2.2 |
| `E1c-bridge-011`, `E1c-drift-check` | Node drift vs image effect (see below) | image / date | both |
| `E2` | Canary vs direct rollout, 100 % failing image | strategy × release | 0.2.2 |
| `E2b` | Same, 30 % failing image | fault rate | 0.2.2 |
| `E2c` | Absolute-count canary metric closes the pre-scrape gap | metric query | 0.2.2 |

Directories prefixed `_pilot-` or `_contaminated-` are runs excluded from analysis and kept as
evidence; the directory name states why.

### Known limitations

- Single-node k3s on a shared-vCPU cloud VM. Absolute throughput drifted ~10 % over the
  campaign (job median 69 s → 72–77 s); `E1c-bridge-011` shows the drift is the node, not the
  worker image. **Compare numbers within one experiment directory only.** `E1c-drift-check`
  re-measures the headline fixed-vs-keda-inflight ratio on a later night (−67 % vs −72 %).
- E1b/E1c ran on worker image 0.1.x, later experiments on 0.2.2 (same pipeline binaries;
  added metrics and fault injection).

## Layout

| Path | Contents |
| --- | --- |
| `cluster/` | Cluster bootstrap (k3s, Prometheus stack, KEDA) |
| `workload/` | Synthetic NGS pipeline container and manifests |
| `experiments/` | Experiment definitions, run scripts, analysis |
| `results/` | Raw measurements and per-experiment summaries/figures |
| `paper/` | Manuscript sources and `figures.py` |
| `docs/` | Methodology notes |

## Reproduce

See `cluster/README.md` (bootstrap) and `experiments/README.md` (runs). Everything runs on a
single 4 vCPU / 8 GB VM. `./paper/figures.py` regenerates the paper figures from
`results/*/summary.csv`.

## Authorship and AI assistance

Experiments were designed, run, and interpreted by the author. Harness scripts, analysis code
and documentation were developed with the assistance of an AI coding assistant (Anthropic
Claude) and reviewed by the author; this is disclosed in the accompanying paper's
acknowledgments in line with IEEE policy.

## License

Apache-2.0. Author: Vipul Bhilare.
