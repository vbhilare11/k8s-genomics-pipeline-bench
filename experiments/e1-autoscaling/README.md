# E1 — Autoscaling under a burst

**Question.** When a burst of jobs arrives, how do backlog-driven scaling (KEDA on queue
length), utilization-driven scaling (HPA on CPU) and a fixed pool compare on latency,
makespan and capacity consumed?

| Mode | Scaler | Range | Signal |
| --- | --- | --- | --- |
| `keda` | KEDA ScaledObject, Redis list | 0–3 | jobs in queue (2 per replica) |
| `hpa` | HorizontalPodAutoscaler | 1–3 | CPU utilization, target 50% |
| `fixed` | none | 3 | — |

**Protocol.** Reset queues → settle 30 s → enqueue N=30 jobs at once → poll queue length
and replica counts every 5 s until all results are in. Three replicates per mode. Every
run records git SHA, `versions.lock`, the Deployment spec, a timeline, per-job timestamps
and the Kubernetes event log.

**Metrics.** Makespan; queue wait p50/p95 (submit → start); time to first scale-up;
replica-seconds (integral of ready replicas, the cost proxy); jobs per replica-minute.

## Run

```bash
./run.sh keda 30 1            # one run
nohup ./run-all.sh 3 30 > ../../results/E1/campaign.log 2>&1 &   # full campaign (~90 min)
./analyze.py                  # summary.csv + figures/
```
