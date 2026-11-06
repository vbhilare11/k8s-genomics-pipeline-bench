#!/usr/bin/env python3
"""NGS pipeline worker.

Blocks on a Redis list for jobs, runs fastp -> bwa mem -> samtools on a fixed
public sample, records timings, pushes a result record, and exposes Prometheus
metrics on :9100. One job at a time per process; parallelism comes from replicas.
"""
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time

import redis
from prometheus_client import Counter, Gauge, Histogram, start_http_server

REDIS_HOST = os.getenv("NGS_REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("NGS_REDIS_PORT", "6379"))
JOB_QUEUE = os.getenv("JOB_QUEUE", "ngs:jobs")
RESULT_QUEUE = os.getenv("RESULT_QUEUE", "ngs:results")
DATA_DIR = os.getenv("DATA_DIR", "/data")
WORK_DIR = os.getenv("WORK_DIR", "/tmp/work")
THREADS = int(os.getenv("THREADS", "1"))
STEPS = [s for s in os.getenv("PIPELINE_STEPS", "fastp,bwa").split(",") if s]
METRICS_PORT = int(os.getenv("METRICS_PORT", "9100"))
WORKER = socket.gethostname()

BUCKETS = (5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600)
JOBS = Counter("ngs_jobs_total", "Jobs processed", ["status"])
JOB_DURATION = Histogram("ngs_job_duration_seconds", "Wall time per job", buckets=BUCKETS)
STEP_DURATION = Histogram("ngs_step_duration_seconds", "Wall time per step", ["step"], buckets=BUCKETS)
QUEUE_WAIT = Histogram("ngs_queue_wait_seconds", "Submit-to-start latency", buckets=BUCKETS)
BUSY = Gauge("ngs_worker_busy", "1 while a job is running")
REDIS_ERRORS = Counter("ngs_redis_errors_total", "Redis connection errors")

# Pre-create labelled series so a first event shows as 0->1 (increase()/rate()
# cannot see a series that is born at its first increment).
for _s in ("ok", "error"):
    JOBS.labels(status=_s)
for _st in ("fastp", "bwa"):
    STEP_DURATION.labels(step=_st)

_stop = False


def _handle_stop(signum, _frame):
    global _stop
    _stop = True
    print(f"[{WORKER}] signal {signum}: finishing current job then exiting", flush=True)


def connect():
    """Connect to Redis, retrying until it is reachable or we are asked to stop."""
    delay = 1.0
    while not _stop:
        try:
            r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True,
                            socket_connect_timeout=3, socket_keepalive=True)
            r.ping()
            print(f"[{WORKER}] connected to redis://{REDIS_HOST}:{REDIS_PORT}", flush=True)
            return r
        except (redis.exceptions.ConnectionError, redis.exceptions.TimeoutError, OSError) as exc:
            REDIS_ERRORS.inc()
            print(f"[{WORKER}] redis unavailable ({exc}); retrying in {delay:.0f}s", flush=True)
            time.sleep(delay)
            delay = min(delay * 2, 15)
    return None


def run_step(name, cmd, log, stdout=None):
    t0 = time.monotonic()
    subprocess.run(cmd, check=True, stdout=stdout or log, stderr=log)
    dt = time.monotonic() - t0
    STEP_DURATION.labels(step=name).observe(dt)
    return dt


def process(job):
    jid = str(job["id"])
    reads = os.path.join(DATA_DIR, "reads", job.get("sample", "sample") + ".fastq.gz")
    ref = os.path.join(DATA_DIR, "ref", "chr20.fa")
    out = os.path.join(WORK_DIR, jid)
    os.makedirs(out, exist_ok=True)
    timings = {}
    aligned = None
    try:
        with open(os.path.join(out, "log.txt"), "w") as log:
            inp = reads
            if "fastp" in STEPS:
                trimmed = os.path.join(out, "trimmed.fastq.gz")
                timings["fastp"] = run_step("fastp", [
                    "fastp", "-i", reads, "-o", trimmed, "-w", str(THREADS),
                    "-j", os.path.join(out, "fastp.json"), "-h", os.path.join(out, "fastp.html"),
                ], log)
                inp = trimmed
            if "bwa" in STEPS:
                sam = os.path.join(out, "aln.sam")
                with open(sam, "w") as sam_fh:
                    timings["bwa"] = run_step("bwa", ["bwa", "mem", "-t", str(THREADS), ref, inp], log, stdout=sam_fh)
                res = subprocess.run(["samtools", "view", "-c", "-F", "4", sam], check=True,
                                     capture_output=True, text=True)
                aligned = int(res.stdout.strip())
    finally:
        shutil.rmtree(out, ignore_errors=True)
    return timings, aligned


def main():
    signal.signal(signal.SIGTERM, _handle_stop)
    signal.signal(signal.SIGINT, _handle_stop)
    start_http_server(METRICS_PORT)
    print(f"[{WORKER}] starting: queue={JOB_QUEUE} steps={STEPS} threads={THREADS}", flush=True)
    r = connect()

    while not _stop and r is not None:
        try:
            item = r.blpop(JOB_QUEUE, timeout=5)
        except (redis.exceptions.ConnectionError, redis.exceptions.TimeoutError, OSError) as exc:
            REDIS_ERRORS.inc()
            print(f"[{WORKER}] redis error during blpop ({exc}); reconnecting", flush=True)
            r = connect()
            continue
        if item is None:
            continue

        job = json.loads(item[1])
        started = time.time()
        if "submitted_at" in job:
            QUEUE_WAIT.observe(max(0.0, started - float(job["submitted_at"])))
        BUSY.set(1)
        t0 = time.monotonic()
        status = "ok"
        timings, aligned, err = {}, None, None
        try:
            timings, aligned = process(job)
        except Exception as exc:  # noqa: BLE001 - record and continue
            status = "error"
            err = repr(exc)
        duration = time.monotonic() - t0
        BUSY.set(0)
        JOB_DURATION.observe(duration)
        JOBS.labels(status=status).inc()
        result = {
            "id": job["id"], "worker": WORKER, "status": status,
            "submitted_at": job.get("submitted_at"), "started_at": started,
            "finished_at": time.time(), "duration_s": round(duration, 3),
            "steps_s": {k: round(v, 3) for k, v in timings.items()},
            "aligned_reads": aligned, "error": err,
        }
        try:
            r.rpush(RESULT_QUEUE, json.dumps(result))
        except (redis.exceptions.ConnectionError, redis.exceptions.TimeoutError, OSError):
            REDIS_ERRORS.inc()
            r = connect()
            if r is not None:
                r.rpush(RESULT_QUEUE, json.dumps(result))
        print(f"[{WORKER}] job {job['id']} {status} {duration:.1f}s {result['steps_s']}", flush=True)

    print(f"[{WORKER}] exiting", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
