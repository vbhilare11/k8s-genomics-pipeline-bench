# E2 — Progressive delivery under a bad release

**Question.** When a new worker version is released while jobs are flowing, how many
jobs does a bad release destroy before it is rolled back, and what does the safer
strategy cost on a good release?

| Mode | Mechanism | Rollback |
| --- | --- | --- |
| `direct` | `kubectl set image` → RollingUpdate | watchdog: Prometheus job-error check every 30 s, `rollout undo` after 2 failures |
| `canary` | Flagger (Kubernetes provider), canary pods beside primary | Flagger: same metric, 30 s interval, threshold 2; promotion after 6 clean checks |

**Bad image.** Same code built with `DATA_DIR=/nonexistent`: every job it takes fails
immediately, so it drains arriving work with failures — the worst case for a queue consumer.

**Protocol.** Fixed 2 replicas (no autoscaler). Steady load of 1 job / 30 s. Release at
t = 90 s; observe to t = 600 s; drain 90 s. 2 modes × {good, bad} × 3 replicates.

**Metrics.** Jobs failed; first/last failure relative to release; exposure window;
time to rollback; for good releases, time to full promotion.

## Run

```bash
./run.sh canary bad 1
nohup ./run-all.sh 3 > ../../results/E2/campaign.log 2>&1 &
./analyze.py
```
