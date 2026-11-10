#!/usr/bin/env bash
# E2 campaign. Usage: ./run-all.sh [replicates=3] [modes="direct canary"] [releases="good bad"]
set -euo pipefail
REPS="${1:-3}"
MODES="${2:-direct canary}"
RELEASES="${3:-good bad}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for rep in $(seq 1 "${REPS}"); do
  for mode in ${MODES}; do
    for release in ${RELEASES}; do
      "${HERE}/run.sh" "${mode}" "${release}" "${rep}"
      sleep 30
    done
  done
done
echo "campaign complete"
