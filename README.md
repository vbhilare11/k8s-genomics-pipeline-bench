# k8s-genomics-pipeline-bench

A reproducible benchmark for operating clinical-style genomic (NGS) pipelines on Kubernetes:
event-driven autoscaling (KEDA vs. HPA) and progressive delivery (canary vs. direct rollout)
measured under controlled, synthetic load using public 1000 Genomes data.

**Status:** work in progress. Results and an accompanying paper will be published here.

## Why

Genomic analysis pipelines are bursty, compute-heavy batch workloads with clinical
turnaround-time requirements. This project measures how common Kubernetes scaling and
delivery mechanisms behave for such workloads, so that hospitals, labs and platform teams
can make evidence-based choices rather than guesses.

## Layout

| Path | Contents |
|---|---|
| `cluster/` | Cluster bootstrap (k3s, Prometheus stack, KEDA) |
| `workload/` | Synthetic NGS pipeline container and manifests |
| `experiments/` | Experiment definitions and run scripts |
| `results/` | Raw measurements (CSV) and generated figures |
| `paper/` | Manuscript sources |
| `docs/` | Methodology notes |

## Reproduce

See `cluster/README.md` (bootstrap) and `experiments/README.md` (runs). Everything runs on a
single 4 vCPU / 8 GB VM.

## License

Apache-2.0. Author: Vipul Bhilare.
