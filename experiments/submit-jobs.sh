#!/usr/bin/env bash
# Enqueue N jobs onto the Redis job list. Usage: ./submit-jobs.sh <count> [prefix]
set -euo pipefail
COUNT="${1:?count required}"
PREFIX="${2:-job}"
NS="${NS:-ngs-bench}"

pod=$(kubectl -n "${NS}" get pod -l app=redis -o jsonpath='{.items[0].metadata.name}')
now=$(date +%s.%N)
args=()
for i in $(seq 1 "${COUNT}"); do
  args+=("{\"id\":\"${PREFIX}-${i}\",\"sample\":\"sample\",\"submitted_at\":${now}}")
done
kubectl -n "${NS}" exec "${pod}" -- redis-cli RPUSH ngs:jobs "${args[@]}" >/dev/null
echo "enqueued ${COUNT} jobs; queue length: $(kubectl -n "${NS}" exec "${pod}" -- redis-cli LLEN ngs:jobs)"
