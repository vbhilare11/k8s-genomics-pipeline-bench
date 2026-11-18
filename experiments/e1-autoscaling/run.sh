#!/usr/bin/env bash
# Autoscaling experiment: one run.
# Usage: ./run.sh <keda|keda-inflight|hpa|fixed> [jobs=30] [replicate=1]
# Env:   EXP=E1 (results subdir)  BURSTS=1  GAP=0 (seconds between bursts)
#        NS=ngs-bench  POLL=5  TIMEOUT=3600  WORKER_IMAGE=ngs-worker:0.2.2
# Writes results/$EXP/<mode>-n<jobs>-b<bursts>-r<rep>/{meta.json,timeline.csv,results.jsonl,events.txt}
# Exits 1 and leaves a CONTAMINATED marker if any job finished with status=error:
# E1 runs use a healthy image, so an error means the cluster was not in the
# expected state (e.g. a *-flaky image left behind by the E2 delivery runs).
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
COOLDOWN="${COOLDOWN:-60}"           # KEDA cooldownPeriod (s)
MIN_REPLICAS="${MIN_REPLICAS:-0}"    # KEDA minReplicaCount
STARTUP_DELAY="${STARTUP_DELAY:-0}"  # simulated worker cold start (s)
WORKER_IMAGE="${WORKER_IMAGE:-ngs-worker:0.2.2}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
OUT="${ROOT}/results/${EXP}/${MODE}-n${JOBS}-b${BURSTS}-r${REP}"
mkdir -p "${OUT}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
rcli() { kubectl -n "${NS}" exec deploy/redis -- redis-cli "$@"; }
ready_replicas() { local r; r=$(kubectl -n "${NS}" get deploy ngs-worker -o jsonpath='{.status.readyReplicas}'); echo "${r:-0}"; }
desired_replicas() { local r; r=$(kubectl -n "${NS}" get deploy ngs-worker -o jsonpath='{.spec.replicas}'); echo "${r:-0}"; }
live_image() { kubectl -n "${NS}" get deploy ngs-worker -o jsonpath='{.spec.template.spec.containers[0].image}'; }

wait_replicas() {  # wait_replicas <n> <timeout_s>
  local want="$1" limit="$2" t=0
  while [[ "$(ready_replicas)" -ne "${want}" || "$(desired_replicas)" -ne "${want}" ]]; do
    if (( t >= limit )); then log "timeout waiting for ${want} replicas"; return 1; fi
    sleep 5; t=$((t + 5))
  done
}

clear_scalers() {
  # Reset everything the delivery experiments (E2*) may have left on the target
  # Deployment. Each of these has contaminated an E1 sweep once:
  #   1. Flagger Canary / primary Deployment / Services -> extra pods on the queue
  #   2. CPU request 500m (E2) instead of 1 CPU        -> different pod density
  #   3. spec image left at a *-broken or *-flaky image after a bad release
  kubectl -n "${NS}" delete scaledobject ngs-worker --ignore-not-found >/dev/null
  kubectl -n "${NS}" delete hpa ngs-worker-cpu --ignore-not-found >/dev/null
  if kubectl -n "${NS}" get canary ngs-worker >/dev/null 2>&1; then
    kubectl -n "${NS}" patch canary ngs-worker --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
    kubectl -n "${NS}" delete canary ngs-worker --ignore-not-found --wait=false >/dev/null
  fi
  kubectl -n "${NS}" delete deploy ngs-worker-primary --ignore-not-found >/dev/null
  kubectl -n "${NS}" delete svc ngs-worker ngs-worker-primary ngs-worker-canary --ignore-not-found >/dev/null
  kubectl -n "${NS}" patch deploy ngs-worker -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"release\":\"baseline\"}},\"spec\":{\"containers\":[{\"name\":\"worker\",\"image\":\"${WORKER_IMAGE}\"}]}}}}" >/dev/null
  kubectl -n "${NS}" set resources deploy/ngs-worker -c worker --requests="cpu=1,memory=1Gi" >/dev/null
  local live; live=$(live_image)
  if [[ "${live}" != "${WORKER_IMAGE}" ]]; then
    log "clear_scalers: image is ${live}, expected ${WORKER_IMAGE}"; exit 1
  fi
}

tune_keda() {
  kubectl -n "${NS}" patch scaledobject ngs-worker --type=merge \
    -p "{\"spec\":{\"cooldownPeriod\":${COOLDOWN},\"minReplicaCount\":${MIN_REPLICAS}}}" >/dev/null
}

configure() {
  kubectl -n "${NS}" set env deploy/ngs-worker STARTUP_DELAY="${STARTUP_DELAY}" >/dev/null
  case "${MODE}" in
    keda)
      clear_scalers
      kubectl apply -f "${HERE}/keda-scaledobject.yaml" >/dev/null
      tune_keda
      log "waiting for KEDA to settle at ${MIN_REPLICAS} (cooldown ${COOLDOWN}s)"
      wait_replicas "${MIN_REPLICAS}" 400
      ;;
    keda-inflight)
      clear_scalers
      kubectl apply -f "${HERE}/keda-inflight.yaml" >/dev/null
      tune_keda
      log "waiting for KEDA (in-flight aware) to settle at ${MIN_REPLICAS} (cooldown ${COOLDOWN}s)"
      wait_replicas "${MIN_REPLICAS}" 400
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

  local sha start_ts image
  sha=$(git -C "${ROOT}" rev-parse HEAD)
  image=$(live_image)
  start_ts=$(date +%s.%N)
  cp "${ROOT}/cluster/versions.lock" "${OUT}/versions.lock"
  kubectl -n "${NS}" get deploy ngs-worker -o yaml > "${OUT}/deployment.yaml"
  log "image=${image} cpu_request=$(kubectl -n "${NS}" get deploy ngs-worker -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')"

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
  local errors; errors=$(grep -c '"status": "error"' "${OUT}/results.jsonl" || true)
  cat > "${OUT}/meta.json" << JSON
{"experiment":"${EXP}","mode":"${MODE}","jobs":${JOBS},"bursts":${BURSTS},"gap_s":${GAP},"replicate":${REP},
 "cooldown_s":${COOLDOWN},"min_replicas":${MIN_REPLICAS},"startup_delay_s":${STARTUP_DELAY},
 "image":"${image}","git_sha":"${sha}","start_ts":${start_ts},"end_ts":${end_ts},
 "makespan_s":$(python3 -c "print(round(${end_ts}-${start_ts},1))"),"completed":${done_n},"errors":${errors}}
JSON
  log "done: ${done_n}/${JOBS} jobs, ${errors} errors, makespan $(python3 -c "print(round(${end_ts}-${start_ts},1))")s"
  if (( errors > 0 )); then
    date -u +%FT%TZ > "${OUT}/CONTAMINATED"
    log "CONTAMINATED: ${errors} jobs failed in an autoscaling run (image=${image}); stopping"
    exit 1
  fi
}

main
