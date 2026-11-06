#!/usr/bin/env bash
# E2 campaign. Usage: ./run-all.sh [replicates=3]
set -euo pipefail
REPS="${1:-3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for rep in $(seq 1 "${REPS}"); do
  for mode in direct canary; do
    for release in good bad; do
      "${HERE}/run.sh" "${mode}" "${release}" "${rep}"
      sleep 30
    done
  done
done
echo "campaign complete"
