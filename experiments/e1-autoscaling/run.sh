#!/usr/bin/env bash
# Autoscaling experiment: one run.
# Usage: ./run.sh <keda|keda-inflight|hpa|fixed> [jobs=30] [replicate=1]
# Env:   EXP=E1 (results subdir)  BURSTS=1  GAP=0 (seconds between bursts)
#        NS=ngs-bench  POLL=5  TIMEOUT=3600
# Writes results/$EXP/<mode>-n<jobs>-b<bursts>-r<rep>/{meta.json,timeline.csv,results.jsonl,events.txt}
set -euo pipefail

MODE="${1:?mode: keda|keda-inflight|hpa|fixed}"
JOBS="${2:-30}"
REP="${3:-1}"
EXP="${EXP:-E1}"
BURSTS="${BURSTS:-1}"
GAP="${GAP:-0}"
NS="${NS:-ngs-bench}"
POLL="${POLL:-5}"
TIMEOUT="${TIMEOUT:-3600}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
OUT="${ROOT}/results/${EXP}/${MODE}-n${JOBS}-b${BURSTS}-r${REP}"
mkdir -p "${OUT}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
rcli() { kubectl -n "${NS}" exec deploy/redis -- redis-cli "$@"; }
ready_replicas() { local r; r=$(kubectl -n "${NS}" get deploy ngs-worker -o jsonpath='{.status.readyReplicas}'); echo "${r:-0}"; }
desired_replicas() { local r; r=$(kubectl -n "${NS}" get deploy ngs-worker -o jsonpath='{.spec.replicas}'); echo "${r:-0}"; }

wait_replicas() {  # wait_replicas <n> <timeout_s>
  local want="$1" limit="$2" t=0
  while [[ "$(ready_replicas)" -ne "${want}" || "$(desired_replicas)" -ne "${want}" ]]; do
    if (( t >= limit )); then log "timeout waiting for ${want} replicas"; return 1; fi
    sleep 5; t=$((t + 5))
  done
}

clear_scalers() {
  kubectl -n "${NS}" delete scaledobject ngs-worker --ignore-not-found >/dev/null
  kubectl -n "${NS}" delete hpa ngs-worker-cpu --ignore-not-found >/dev/null
}

configure() {
  case "${MODE}" in
    keda)
      clear_scalers
      kubectl apply -f "${HERE}/keda-scaledobject.yaml" >/dev/null
      log "waiting for KEDA to scale to 0 (cooldown)"
      wait_replicas 0 240
      ;;
    keda-inflight)
      clear_scalers
      kubectl apply -f "${HERE}/keda-inflight.yaml" >/dev/null
      log "waiting for KEDA (in-flight aware) to scale to 0 (cooldown)"
      wait_replicas 0 240
      ;;
    hpa)
      clear_scalers
      kubectl -n "${NS}" scale deploy ngs-worker --replicas=1 >/dev/null
      kubectl apply -f "${HERE}/hpa-cpu.yaml" >/dev/null
      wait_replicas 1 120
      ;;
    fixed)
      clear_scalers
      kubectl -n "${NS}" scale deploy ngs-worker --replicas=3 >/dev/null
      wait_replicas 3 120
      ;;
    *) echo "unknown mode ${MODE}" >&2; exit 2 ;;
  esac
}

poller() {  # background: ts,queue_len,ready,desired every $POLL seconds
  echo "ts,queue_len,ready_replicas,desired_replicas" > "${OUT}/timeline.csv"
  while true; do
    printf '%s,%s,%s,%s\n' "$(date +%s)" "$(rcli LLEN ngs:jobs | tr -d '[:space:]')" \
      "$(ready_replicas)" "$(desired_replicas)" >> "${OUT}/timeline.csv"
    sleep "${POLL}"
  done
}

submit_pattern() {  # background: BURSTS bursts of JOBS/BURSTS jobs, GAP seconds apart
  local per=$(( JOBS / BURSTS )) b
  for b in $(seq 1 "${BURSTS}"); do
    local n="${per}"
    if (( b == BURSTS )); then n=$(( JOBS - per * (BURSTS - 1) )); fi
    log "burst ${b}/${BURSTS}: submitting ${n} jobs"
    "${ROOT}/experiments/submit-jobs.sh" "${n}" "${EXP}-${MODE}-r${REP}-b${b}"
    if (( b < BURSTS )); then sleep "${GAP}"; fi
  done
}

main() {
  log "${EXP} mode=${MODE} jobs=${JOBS} bursts=${BURSTS} gap=${GAP}s rep=${REP} -> ${OUT}"
  configure
  rcli DEL ngs:jobs ngs:results >/dev/null
  sleep 30

  local sha start_ts
  sha=$(git -C "${ROOT}" rev-parse HEAD)
  start_ts=$(date +%s.%N)
  cp "${ROOT}/cluster/versions.lock" "${OUT}/versions.lock"
  kubectl -n "${NS}" get deploy ngs-worker -o yaml > "${OUT}/deployment.yaml"

  poller & local poller_pid=$!
  submit_pattern & local submit_pid=$!
  trap 'kill ${poller_pid} ${submit_pid} 2>/dev/null || true' EXIT

  local t=0 done_n=0
  while :; do
    done_n=$(rcli LLEN ngs:results | tr -d '[:space:]')
    if [[ "${done_n}" -ge "${JOBS}" ]]; then break; fi
    if (( t >= TIMEOUT )); then log "timeout: ${done_n}/${JOBS} done"; break; fi
    sleep "${POLL}"; t=$((t + POLL))
  done
  local end_ts; end_ts=$(date +%s.%N)
  kill "${poller_pid}" "${submit_pid}" 2>/dev/null || true
  trap - EXIT

  rcli LRANGE ngs:results 0 -1 > "${OUT}/results.jsonl"
  kubectl -n "${NS}" get events --sort-by=.lastTimestamp > "${OUT}/events.txt" 2>/dev/null || true
  cat > "${OUT}/meta.json" << JSON
{"experiment":"${EXP}","mode":"${MODE}","jobs":${JOBS},"bursts":${BURSTS},"gap_s":${GAP},"replicate":${REP},
 "git_sha":"${sha}","start_ts":${start_ts},"end_ts":${end_ts},
 "makespan_s":$(python3 -c "print(round(${end_ts}-${start_ts},1))"),"completed":${done_n}}
JSON
  log "done: ${done_n}/${JOBS} jobs, makespan $(python3 -c "print(round(${end_ts}-${start_ts},1))")s"
}

main
