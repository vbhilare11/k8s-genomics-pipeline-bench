#!/usr/bin/env bash
# Full E1 campaign: 3 modes x N replicates. Usage: ./run-all.sh [replicates=3] [jobs=30]
set -euo pipefail
REPS="${1:-3}"
JOBS="${2:-30}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for rep in $(seq 1 "${REPS}"); do
  for mode in fixed hpa keda; do
    "${HERE}/run.sh" "${mode}" "${JOBS}" "${rep}"
    sleep 60
  done
done
echo "campaign complete"
