#!/usr/bin/env bash
# Campaign runner. Usage: ./run-all.sh [replicates=3] [jobs=30] [modes="fixed hpa keda keda-inflight"]
# Env passthrough: EXP, BURSTS, GAP (see run.sh).
set -euo pipefail
REPS="${1:-3}"
JOBS="${2:-30}"
MODES="${3:-fixed hpa keda keda-inflight}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for rep in $(seq 1 "${REPS}"); do
  for mode in ${MODES}; do
    "${HERE}/run.sh" "${mode}" "${JOBS}" "${rep}"
    sleep 60
  done
done
echo "campaign complete"
