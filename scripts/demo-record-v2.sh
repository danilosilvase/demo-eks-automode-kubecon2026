#!/bin/bash
# =============================================================================
# EKS Auto Mode booth demo v2: silent-loop friendly
# Changes from v1 (reviewer feedback): pinned step banner, "watch" hints,
# Graviton via the same Deployment, measured On-Demand -> Spot swap with prices,
# neutral waits, node diff captions, in-place timers, cost scoreboard.
# Every number shown is read live from the cluster or the eks-node-viewer pane.
# =============================================================================
set -u
NAMESPACE="demo-app"
MANIFESTS_DIR="${MANIFESTS_DIR:-manifests}"
PAUSE="${PAUSE:-8}"
TSOCK="${TSOCK:-ekrec}"
TOP_PANE="${TOP_PANE:-eks-rec:0.0}"

G=$'\033[1;32m'; Y=$'\033[1;33m'; C=$'\033[1;36m'; B=$'\033[1m'; N=$'\033[0m'

banner() { tmux -L "$TSOCK" set -g status-left " ${1} " >/dev/null 2>&1 || true; }
type_cmd() { echo ""; echo -n "  \$ "; for (( i=0; i<${#1}; i++ )); do echo -n "${1:$i:1}"; sleep 0.03; done; echo ""; sleep 0.4; }
run() { type_cmd "$1"; eval "$1"; }
# LIVE=1: wait for Enter instead of sleeping, so the presenter sets the pace
pause() {
  if [ "${LIVE:-0}" = "1" ]; then printf "\n  \033[2m[Enter] next\033[0m"; read -r _; else sleep "${1:-$PAUSE}"; fi
}
ok() { printf "\n    ${G}✓ %s${N}\n" "$1"; }
caption() { printf "\n  ${Y}▶ %s${N}\n" "$1"; }
watch_hint() { printf "  ${C}Watch: %s${N}\n" "$1"; }
header() { clear; banner "STEP $1/7 · $2"; printf "\n  ${B}%s/7  %s${N}\n" "$1" "$2"; echo "  ────────────────────────────────────────────"; }

# Short node table: name, status, age, type, arch, capacity
nodes() {
  kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type 2>/dev/null \
    | awk '{print $1, $2, $4, $6, $7, $8}' | column -t | sed 's/^/  /'
}
node_count() { kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' '; }
running() { kubectl get pods -n "$NAMESPACE" -l app="$1" --no-headers 2>/dev/null | grep -c Running; }
# name=type map of current nodes
snapshot() { kubectl get nodes --no-headers -o custom-columns=N:.metadata.name,T:.metadata.labels.node\\.kubernetes\\.io/instance-type 2>/dev/null; }
# Total cost line and per-type price, read from the eks-node-viewer pane
cost() { tmux -L "$TSOCK" capture-pane -p -t "$TOP_PANE" 2>/dev/null | grep -oE '\$[0-9.]+/hour' | head -1; }
price_of() { tmux -L "$TSOCK" capture-pane -p -t "$TOP_PANE" 2>/dev/null | grep -oE "${1}/\\\$[0-9.]+" | head -1 | cut -d'$' -f2; }
placement() {
  local nodes; nodes=$(kubectl get pods -n "$NAMESPACE" -l app="$1" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ')
  [ -z "${nodes// /}" ] && return 0
  # shellcheck disable=SC2086
  kubectl get nodes $nodes --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type,A:.metadata.labels.kubernetes\\.io/arch,C:.metadata.labels.karpenter\\.sh/capacity-type \
    | awk '{print $1" "$2" "$3}' | sort -u | paste -sd ',' - | sed 's/,/, /g'
}
# Report nodes Auto Mode removed since the last snapshot
report_removed() {
  local before="$1" now gone
  now=$(snapshot | awk '{print $1}')
  gone=$(echo "$before" | while read -r n t; do [ -n "$n" ] && ! echo "$now" | grep -qx "$n" && echo "$t"; done | paste -sd ',' - | sed 's/,/, /g')
  [ -n "$gone" ] && printf "  ${C}↺ Since last step Auto Mode removed under-used node(s): %s (consolidation)${N}\n" "$gone"
}
# New nodes since snapshot, as "type arch capacity"
new_nodes() {
  local before="$1" names=""
  for n in $(snapshot | awk '{print $1}'); do echo "$before" | awk '{print $1}' | grep -qx "$n" || names="$names $n"; done
  [ -z "${names// /}" ] && return 0
  # shellcheck disable=SC2086
  kubectl get nodes $names --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type,A:.metadata.labels.kubernetes\\.io/arch,C:.metadata.labels.karpenter\\.sh/capacity-type \
    | awk '{print $1" "$2" "$3}' | paste -sd ',' - | sed 's/,/, /g'
}
# In-place wait: wait_until <timeout> <label-fn> <done-test>
wait_until() {
  local timeout="$1" label="$2" test="$3" start now el
  start=$(date +%s)
  while true; do
    now=$(date +%s); el=$(( now - start ))
    printf "\r    ⏱ %3ds   %s          " "$el" "$($label)"
    eval "$test" && break
    [ "$el" -ge "$timeout" ] && break
    sleep 3
  done
  echo ""
  WAITED=$(( $(date +%s) - start ))
}

# ─── Intro card ──────────────────────────────────────────────────────────────
banner "Amazon EKS Auto Mode · live demo"
clear
printf "\n\n  ${B}Amazon EKS Auto Mode: deploy pods, AWS runs the nodes${N}\n\n"
echo "  TOP:    live EC2 nodes (eks-node-viewer): type, Spot or On-Demand, CPU/memory, \$/hour"
echo "  BOTTOM: the kubectl commands, with timers measured live"
echo ""
echo "  You will see: a node appear on demand, a cheaper Spot node take over,"
echo "  Graviton with no rebuild, right-sized nodes, a burst to 30 pods, and idle nodes removed."
pause 8

# ─── 1. Zero config ─────────────────────────────────────────────────────────
header 1 "Deploy an app, get a node (nothing to install)"
watch_hint "Top pane: a node appears for the pending pods"
run "kubectl apply -f ${MANIFESTS_DIR}/01-namespace.yaml"
run "kubectl apply -f ${MANIFESTS_DIR}/02-sample-app.yaml -f ${MANIFESTS_DIR}/06-pod-disruption-budget.yaml"
lbl1() { echo "nodes: $(node_count)   pods running: $(running sample-app)/3"; }
wait_until 150 lbl1 '[ "$(running sample-app)" -ge 3 ]'
T1=$WAITED; ok "Node launched and 3 pods running in ${T1}s"
sleep 4
run "nodes"
OD_TYPE=$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type 2>/dev/null | head -1)
OD_PRICE=$(price_of "$OD_TYPE"); START_COST=$(cost)
caption "You deployed an app. Auto Mode picked, launched and joined a node in ${T1}s. No Karpenter to install."
pause

# ─── 2. Spot ────────────────────────────────────────────────────────────────
header 2 "One NodePool: allow Spot + On-Demand, x86 + Graviton"
watch_hint "Top pane: a Spot node joins, then the On-Demand node is drained and removed"
SNAP=$(snapshot)
run "kubectl apply -f ${MANIFESTS_DIR}/00-cost-optimized-nodepool.yaml"
lbl2() { echo "Spot nodes: $(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')   On-Demand nodes: $(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')"; }
wait_until 180 lbl2 '[ "$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d " ")" -eq 0 ] && [ "$(running sample-app)" -ge 3 ]'
T2=$WAITED
SPOT_TYPE=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type 2>/dev/null | head -1)
sleep 3; SPOT_PRICE=$(price_of "$SPOT_TYPE")
run "nodes"
if [ "$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] && [ -n "$SPOT_TYPE" ]; then
  ok "On-Demand node replaced by Spot in ${T2}s"
  caption "No app change. Auto Mode moved the app from On-Demand ${OD_TYPE} (\$${OD_PRICE:-?}/h) to Spot ${SPOT_TYPE} (\$${SPOT_PRICE:-?}/h)."
  SWAP="On-Demand ${OD_TYPE} \$${OD_PRICE:-?}/h → Spot ${SPOT_TYPE} \$${SPOT_PRICE:-?}/h in ${T2}s"
else
  caption "Spot capacity added: $(new_nodes "$SNAP"). The On-Demand node is still draining."
  SWAP="Spot node added in ${T2}s"
fi
pause

# ─── 3. Graviton, same Deployment ───────────────────────────────────────────
header 3 "Same app, same image, now on AWS Graviton (arm64)"
watch_hint "Top pane: an arm64 node appears, the app moves, no image rebuild"
report_removed "$SNAP"; SNAP=$(snapshot)
run "kubectl patch deployment sample-app -n ${NAMESPACE} -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/arch\":\"arm64\"}}}}}'"
lbl3() { echo "nodes: $(node_count)   pods on arm64: $(kubectl get pods -n $NAMESPACE -l app=sample-app -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | xargs -r kubectl get nodes -l kubernetes.io/arch=arm64 --no-headers 2>/dev/null | wc -l | tr -d ' ') node(s)"; }
wait_until 180 lbl3 'kubectl rollout status deployment/sample-app -n $NAMESPACE --timeout=1s >/dev/null 2>&1'
T3=$WAITED; ok "Rollout to Graviton finished in ${T3}s"
GRAV_ON=$(placement sample-app)
run "nodes"
caption "Same Deployment and image, now on ${GRAV_ON}. arm64 = AWS Graviton. No rebuild."
pause

# ─── 4. CPU-heavy ───────────────────────────────────────────────────────────
header 4 "CPU-heavy pods: 2 pods × 2 vCPU"
watch_hint "Top pane: Karpenter chooses an instance that fits the CPU request"
report_removed "$SNAP"; SNAP=$(snapshot)
run "kubectl apply -f ${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"
lbl4() { echo "nodes: $(node_count)   pods running: $(running compute-intensive)/2"; }
wait_until 150 lbl4 '[ "$(running compute-intensive)" -ge 2 ]'
T4=$WAITED; ok "CPU pods running in ${T4}s"
NEW4=$(new_nodes "$SNAP")
run "nodes"
caption "${NEW4:+New node: ${NEW4}. }CPU pods run on: $(placement compute-intensive)."
pause

# ─── 5. Memory-heavy ────────────────────────────────────────────────────────
header 5 "Memory-heavy pods: 2 pods × 8 GiB"
watch_hint "Top pane: memory bars; new capacity only if existing nodes are full"
report_removed "$SNAP"; SNAP=$(snapshot)
run "kubectl apply -f ${MANIFESTS_DIR}/04-memory-intensive-workload.yaml"
lbl5() { echo "nodes: $(node_count)   pods running: $(running memory-intensive)/2"; }
wait_until 150 lbl5 '[ "$(running memory-intensive)" -ge 2 ]'
T5=$WAITED; ok "Memory pods running in ${T5}s"
NEW5=$(new_nodes "$SNAP")
run "nodes"
caption "${NEW5:+New node: ${NEW5}. }Memory pods run on: $(placement memory-intensive)."
pause

# ─── 6. Burst ───────────────────────────────────────────────────────────────
header 6 "Burst: scale the app from 3 to 30 pods"
watch_hint "Top pane: new capacity for the pending pods"
report_removed "$SNAP"; SNAP=$(snapshot)
NB6=$(node_count)
run "kubectl scale deployment sample-app -n ${NAMESPACE} --replicas=30"
lbl6() { echo "nodes: $(node_count)   pods running: $(running sample-app)/30"; }
wait_until 240 lbl6 '[ "$(running sample-app)" -ge 30 ]'
T6=$WAITED; NA6=$(node_count)
SUFFIX=""; [ "$T6" -lt 60 ] && SUFFIX=" (under a minute)"
ok "30 pods running in ${T6}s${SUFFIX}"
sleep 4; PEAK_COST=$(cost); PEAK_NODES=$(node_count)
run "nodes"
caption "30 pods: ${NB6} → ${NA6} nodes, all running in ${T6}s${SUFFIX}. Cluster now ${PEAK_COST}."
pause

# ─── 7. Consolidation ──────────────────────────────────────────────────────
header 7 "Scale down: Auto Mode removes nodes you no longer need"
watch_hint "Top pane: nodes go to Deleting and \$/hour drops"
SNAP=$(snapshot); NB7=$(node_count)
run "kubectl scale deployment compute-intensive memory-intensive -n ${NAMESPACE} --replicas=0"
run "kubectl scale deployment sample-app -n ${NAMESPACE} --replicas=3"
echo "  Pods scaled down. Auto Mode waits 30s (consolidateAfter), then drains under-used nodes."
lbl7() { echo "nodes: $(node_count)   cluster cost: $(cost)"; }
wait_until 240 lbl7 '[ "$(node_count)" -le 1 ]'
T7=$WAITED; NA7=$(node_count)
sleep 4; END_COST=$(cost)
ok "${NB7} → ${NA7} node(s) in ${T7}s"
run "nodes"
caption "Empty nodes deleted, under-used nodes drained (PDBs respected). ${PEAK_COST} → ${END_COST}."
pause

# ─── Recap ──────────────────────────────────────────────────────────────────
banner "Amazon EKS Auto Mode · results from this run"
clear
printf "\n\n  ${B}Measured in this run${N}\n\n"
printf "  %-34s %s\n" "First node + 3 pods:" "${T1}s, nothing installed"
printf "  %-34s %s\n" "Cheaper capacity:" "${SWAP}"
printf "  %-34s %s\n" "Same image on Graviton:" "${T3}s rollout, ${GRAV_ON}"
printf "  %-34s %s\n" "Burst to 30 pods:" "${T6}s, ${NB6} → ${NA6} nodes"
printf "  %-34s %s\n" "Scale down:" "${NB7} → ${NA7} node(s) in ${T7}s"
echo ""
printf "  %-34s %s\n" "Cluster cost, app only (start):" "${START_COST}"
printf "  %-34s %s\n" "Cluster cost at peak (${PEAK_NODES} nodes):" "${PEAK_COST}"
printf "  %-34s %s\n" "Cluster cost, app only (end):" "${END_COST}"
echo ""
echo "  Instance choices vary run to run: Karpenter picks the cheapest fit at that moment."
pause 15
