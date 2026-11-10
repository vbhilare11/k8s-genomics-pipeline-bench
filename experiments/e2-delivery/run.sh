#!/usr/bin/env bash
# E2 progressive-delivery experiment: one run.
# Usage: ./run.sh <direct|canary> <good|bad> [replicate=1]
# Env: EXP=E2 REPLICAS=2 LOAD_INTERVAL=30 PRE=90 DURATION=600 NS=ngs-bench POLL=5
#      GOOD_IMAGE=ngs-worker:0.2.1 BAD_IMAGE=ngs-worker:0.2.1-broken
set -euo pipefail

MODE="${1:?mode: direct|canary}"
RELEASE="${2:?release: good|bad}"
REP="${3:-1}"
EXP="${EXP:-E2}"
REPLICAS="${REPLICAS:-2}"
LOAD_INTERVAL="${LOAD_INTERVAL:-20}"
PRE="${PRE:-90}"
DURATION="${DURATION:-600}"
NS="${NS:-ngs-bench}"
POLL="${POLL:-5}"
GOOD_IMAGE="${GOOD_IMAGE:-ngs-worker:0.2.1}"
BAD_IMAGE="${BAD_IMAGE:-ngs-worker:0.2.1-broken}"
CPU_REQUEST="${CPU_REQUEST:-500m}"   # 2 primary + 2 canary pods must fit on a 4 vCPU node

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
OUT="${ROOT}/results/${EXP}/${MODE}-${RELEASE}-r${REP}"
mkdir -p "${OUT}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
rcli() { kubectl -n "${NS}" exec deploy/redis -- redis-cli "$@"; }
ready() { local r; r=$(kubectl -n "${NS}" get deploy "$1" -o jsonpath='{.status.readyReplicas}' 2>/dev/null); echo "${r:-0}"; }
updated() { local r; r=$(kubectl -n "${NS}" get deploy "$1" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null); echo "${r:-0}"; }
exists() { kubectl -n "${NS}" get "$1" "$2" >/dev/null 2>&1 && echo present || echo absent; }
live_image() {  # image of the deployment currently serving (primary under Flagger)
  if [[ "$(exists deploy ngs-worker-primary)" == present ]]; then
    kubectl -n "${NS}" get deploy ngs-worker-primary -o jsonpath='{.spec.template.spec.containers[0].image}'
  else
    kubectl -n "${NS}" get deploy ngs-worker -o jsonpath='{.spec.template.spec.containers[0].image}'
  fi
}
canary_phase() { kubectl -n "${NS}" get canary ngs-worker -o jsonpath='{.status.phase}' 2>/dev/null || echo "-"; }

wait_until() {  # wait_until <timeout_s> <command...>  (command must succeed)
  local limit="$1" t=0; shift
  until "$@"; do
    if (( t >= limit )); then log "timeout after ${limit}s waiting for: $*"; return 1; fi
    sleep 5; t=$((t + 5))
  done
}
is_absent() { [[ "$(exists "$1" "$2")" == absent ]]; }
is_ready() { [[ "$(ready "$1")" -ge "$2" ]]; }
canary_settled() { case "$(canary_phase)" in Initialized|Succeeded) return 0 ;; *) return 1 ;; esac; }

reset_plain_deployment() {
  kubectl -n "${NS}" delete scaledobject ngs-worker --ignore-not-found >/dev/null
  kubectl -n "${NS}" delete hpa ngs-worker-cpu --ignore-not-found >/dev/null
  if [[ "$(exists canary ngs-worker)" == present ]]; then
    log "removing existing Canary and Flagger-managed objects"
    kubectl -n "${NS}" patch canary ngs-worker --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
    kubectl -n "${NS}" delete canary ngs-worker --ignore-not-found --wait=false >/dev/null
    wait_until 120 is_absent canary ngs-worker
  fi
  kubectl -n "${NS}" delete deploy ngs-worker-primary --ignore-not-found >/dev/null
  kubectl -n "${NS}" delete svc ngs-worker ngs-worker-primary ngs-worker-canary --ignore-not-found >/dev/null
  wait_until 120 is_absent deploy ngs-worker-primary
  kubectl -n "${NS}" patch deploy ngs-worker -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"release\":\"baseline\"}},\"spec\":{\"containers\":[{\"name\":\"worker\",\"image\":\"${GOOD_IMAGE}\"}]}}}}" >/dev/null
  kubectl -n "${NS}" set resources deploy/ngs-worker -c worker --requests="cpu=${CPU_REQUEST},memory=768Mi" >/dev/null
  kubectl -n "${NS}" scale deploy ngs-worker --replicas="${REPLICAS}" >/dev/null
  kubectl -n "${NS}" rollout status deploy/ngs-worker --timeout=180s >/dev/null
  wait_until 120 is_ready ngs-worker "${REPLICAS}"
}

configure() {
  reset_plain_deployment
  if [[ "${MODE}" == "canary" ]]; then
    kubectl apply -f "${HERE}/metric-template.yaml" -f "${HERE}/canary.yaml" >/dev/null
    log "waiting for Flagger initialisation (phase: $(canary_phase))"
    wait_until 480 canary_settled
    wait_until 180 is_ready ngs-worker-primary "${REPLICAS}"
    log "Flagger ready (phase: $(canary_phase)), primary=${REPLICAS} live=$(live_image)"
  fi
}

do_release() {
  local img="${GOOD_IMAGE}"
  [[ "${RELEASE}" == "bad" ]] && img="${BAD_IMAGE}"
  # One patch = one Deployment revision; a two-step release would leave an
  # intermediate (still-broken) revision for `rollout undo` to land on.
  kubectl -n "${NS}" patch deploy ngs-worker -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"release\":\"${EXP}-${MODE}-${RELEASE}-r${REP}\"}},\"spec\":{\"containers\":[{\"name\":\"worker\",\"image\":\"${img}\"}]}}}}" >/dev/null
  date +%s.%N > "${OUT}/t_release"
  log "released ${RELEASE} (${img}) via ${MODE}"
}

poller() {
  echo "ts,queue_len,live_image,ready_primary,ready_target,canary_phase,updated_target" > "${OUT}/timeline.csv"
  while true; do
    printf '%s,%s,%s,%s,%s,%s,%s\n' "$(date +%s)" "$(rcli LLEN ngs:jobs | tr -d '[:space:]')" \
      "$(live_image)" "$(ready ngs-worker-primary)" "$(ready ngs-worker)" "$(canary_phase)" \
      "$(updated ngs-worker)" >> "${OUT}/timeline.csv"
    sleep "${POLL}"
  done
}

loadgen() {
  local i=0
  while true; do
    i=$((i + 1))
    "${ROOT}/experiments/submit-jobs.sh" 1 "${EXP}-${MODE}-${RELEASE}-r${REP}-j${i}" >/dev/null
    sleep "${LOAD_INTERVAL}"
  done
}

main() {
  log "${EXP} mode=${MODE} release=${RELEASE} rep=${REP} -> ${OUT}"
  configure
  rcli DEL ngs:jobs ngs:results >/dev/null
  sleep 20

  local sha start_ts
  sha=$(git -C "${ROOT}" rev-parse HEAD)
  start_ts=$(date +%s.%N)
  cp "${ROOT}/cluster/versions.lock" "${OUT}/versions.lock"
  rm -f "${OUT}/t_undo"

  poller & local poller_pid=$!
  loadgen & local load_pid=$!
  local wd_pid=""
  if [[ "${MODE}" == "direct" ]]; then
    "${HERE}/watchdog.sh" "${OUT}/t_undo" > "${OUT}/watchdog.log" 2>&1 & wd_pid=$!
  fi
  trap 'kill ${poller_pid} ${load_pid} ${wd_pid} 2>/dev/null || true' EXIT

  sleep "${PRE}"
  do_release
  sleep $(( DURATION - PRE ))

  kill "${load_pid}" 2>/dev/null || true
  log "load stopped; draining"
  sleep 90
  local end_ts; end_ts=$(date +%s.%N)
  kill "${poller_pid}" ${wd_pid} 2>/dev/null || true
  trap - EXIT

  rcli LRANGE ngs:results 0 -1 > "${OUT}/results.jsonl"
  kubectl -n "${NS}" get events --sort-by=.lastTimestamp > "${OUT}/events.txt" 2>/dev/null || true
  kubectl -n "${NS}" describe canary ngs-worker > "${OUT}/canary-describe.txt" 2>/dev/null || true
  local t_undo="null"; [[ -f "${OUT}/t_undo" ]] && t_undo=$(cat "${OUT}/t_undo")
  cat > "${OUT}/meta.json" << JSON
{"experiment":"${EXP}","mode":"${MODE}","release":"${RELEASE}","replicate":${REP},
 "replicas":${REPLICAS},"cpu_request":"${CPU_REQUEST}","load_interval_s":${LOAD_INTERVAL},"pre_s":${PRE},"duration_s":${DURATION},
 "good_image":"${GOOD_IMAGE}","bad_image":"${BAD_IMAGE}","git_sha":"${sha}",
 "start_ts":${start_ts},"t_release":$(cat "${OUT}/t_release"),"t_undo":${t_undo},"end_ts":${end_ts}}
JSON
  log "done: $(grep -c '"status": "ok"' "${OUT}/results.jsonl" || true) ok, $(grep -c '"status": "error"' "${OUT}/results.jsonl" || true) failed"
}

main
