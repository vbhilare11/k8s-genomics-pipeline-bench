# Workload

A queue-driven NGS worker. Each job runs `fastp` (QC/trim) then `bwa mem` (alignment to
GRCh38 chr20) then `samtools view -c` on a fixed public sample, and records timings.

| Item | Source |
| --- | --- |
| Reads | 1000 Genomes HG00096, run SRR062634, first 200k reads of R1 |
| Reference | UCSC hg38 `chr20.fa` |
| Tools | fastp, bwa, samtools (Debian bookworm packages) |

## Build

```bash
docker build -t ngs-worker:0.1.1 workload/
docker save ngs-worker:0.1.1 | k3s ctr images import -
```

## Prepare data (once, ~5 minutes)

```bash
mkdir -p /data/ngs && chown 65532:65532 /data/ngs
docker run --rm -v /data/ngs:/data --entrypoint /app/prepare-data.sh ngs-worker:0.1.1
```

## Deploy

```bash
kubectl apply -f workload/k8s/
kubectl -n ngs-bench get pods
```

## Metrics (port 9100)

`ngs_jobs_total{status}`, `ngs_job_duration_seconds`, `ngs_step_duration_seconds{step}`,
`ngs_queue_wait_seconds`, `ngs_worker_busy`. Scraped by Prometheus via a `PodMonitor`.

## Job format

```json
{"id": "job-1", "sample": "sample", "submitted_at": 1730000000.0}
```

Results are pushed to the `ngs:results` list as JSON with per-step timings and the
aligned read count.
