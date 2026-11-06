#!/usr/bin/env bash
# Direct-rollout watchdog: every INTERVAL s, query Prometheus for job errors in the
# last minute; after THRESHOLD failed checks, run `kubectl rollout undo` once.
# Mirrors Flagger's analysis interval/threshold so the comparison is like-for-like.
# Usage: watchdog.sh <outfile>   (writes the undo timestamp to <outfile>)
set -euo pipefail
OUTFILE="${1:?outfile}"
NS="${NS:-ngs-bench}"
INTERVAL="${INTERVAL:-30}"
THRESHOLD="${THRESHOLD:-2}"
PROM="${PROM:-http://$(kubectl -n monitoring get svc monitoring-kube-prometheus-prometheus -o jsonpath='{.spec.clusterIP}'):9090}"
QUERY='sum(increase(ngs_jobs_total{namespace="ngs-bench",status="error"}[1m])) or vector(0)'

failed=0
while true; do
  v=$(curl -s --get "${PROM}/api/v1/query" --data-urlencode "query=${QUERY}" \
      | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(float(d[0]["value"][1]) if d else 0.0)')
  if python3 -c "import sys; sys.exit(0 if ${v} > 0 else 1)"; then
    failed=$((failed + 1))
    echo "[watchdog] errors/min=${v} failed_checks=${failed}"
    if (( failed >= THRESHOLD )); then
      kubectl -n "${NS}" rollout undo deploy/ngs-worker
      date +%s.%N > "${OUTFILE}"
      echo "[watchdog] rollout undo issued"
      exit 0
    fi
  fi
  sleep "${INTERVAL}"
done
