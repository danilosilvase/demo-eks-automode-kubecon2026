#!/bin/bash
# =============================================================================
# EKS Auto Mode booth demo v3: silent loop + live (LIVE=1)
# v3 adds (round-2 reviews): results tally pinned in the status bar, live +/- node events
# during waits, correct arm64 counter, honest cost scope, measured step 7 caption.
# Changes from v1 (reviewer feedback): pinned step banner, "watch" hints,
# Graviton via the same Deployment, measured On-Demand -> Spot swap with prices,
# neutral waits, node diff captions, in-place timers, cost scoreboard.
# Every number shown is read live from the cluster or the eks-node-viewer pane.
# =============================================================================
set -u
NAMESPACE="demo-app"
MANIFESTS_DIR="${MANIFESTS_DIR:-manifests}"
PAUSE="${PAUSE:-12}"
TSOCK="${TSOCK:-ekrec}"
TOP_PANE="${TOP_PANE:-eks-rec:0.0}"

G=$'\033[1;32m'; CAP=$'\033[1;97;44m'; C=$'\033[1;36m'; M=$'\033[1;35m'; B=$'\033[1m'; N=$'\033[0m'

banner() { tmux -L "$TSOCK" set -g status-left " ${1} " >/dev/null 2>&1 || true; }
type_cmd() { echo ""; echo -n "  \$ "; for (( i=0; i<${#1}; i++ )); do echo -n "${1:$i:1}"; sleep 0.03; done; echo ""; sleep 0.4; }
run() { type_cmd "$1"; eval "$1"; }
# LIVE=1: wait for Enter instead of sleeping, so the presenter sets the pace
# Drop keys pressed while a step was running. Fractional read timeouts need bash 4+;
# macOS /bin/bash is 3.2, so skip the flush there instead of printing an error.
flush_keys() { [ "${BASH_VERSINFO[0]:-3}" -ge 4 ] || return 0; while read -r -t 0.05 _; do :; done; }
pause() {
  if [ "${LIVE:-0}" = "1" ]; then
    flush_keys
    printf "\n  \033[2m[Enter] next\033[0m"; read -r _
  else sleep "${1:-$PAUSE}"; fi
}
ok() { printf "\n    ${G}✓ %s${N}\n" "$1"; }
# Results tally: second status-bar line that keeps every measured result visible
TALLY=""
tally() {
  TALLY="${TALLY:+$TALLY  ·  }$1"
  tmux -L "$TSOCK" set -g status 2 >/dev/null 2>&1 || true
  tmux -L "$TSOCK" set -g 'status-format[1]' "#[bg=colour236,fg=colour255,bold] ${TALLY//#/##}" >/dev/null 2>&1 || true
}
caption() { printf "\n  ${CAP} ▶ %s ${N}\n" "$1"; }
watch_hint() { printf "  ${C}Watch %s${N}\n" "$1"; }
header() { clear; banner "STEP $1/7 · $2"; printf "\n  ${B}%s/7  %s${N}\n" "$1" "$2"; }

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
  [ -n "$gone" ] && printf "  ${M}↺ Since the last step Auto Mode removed node(s) no longer needed: %s${N}\n" "$gone"
}
# New nodes since snapshot, as "type arch capacity"
new_nodes() {
  local before="$1" names=""
  for n in $(snapshot | awk '{print $1}'); do echo "$before" | awk '{print $1}' | grep -qx "$n" || names="$names $n"; done
  [ -z "${names// /}" ] && return 0
  # shellcheck disable=SC2086
  kubectl get nodes $names --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type,A:.metadata.labels.kubernetes\\.io/arch,C:.metadata.labels.karpenter\\.sh/capacity-type \
    | while read -r t a c; do echo "$t $a $c \$$(price_of "$t" </dev/null)/h"; done | paste -sd ',' - | sed 's/,/, /g'
}
# In-place wait with live node events: wait_until <timeout> <label-fn> <done-test>
# Prints "+ type joined" / "- type removed" as they happen, and one timer line updated in place.
wait_until() {
  local timeout="$1" label="$2" test="$3" start el prev cur n t
  start=$(date +%s); prev=$(snapshot)
  while true; do
    el=$(( $(date +%s) - start ))
    cur=$(snapshot)
    if [ "$cur" != "$prev" ]; then
      while read -r n t; do [ -n "$n" ] && ! echo "$prev" | grep -q "^$n " && printf "\r    ${G}+ %s joined (%ds)${N}                              \n" "$t" "$el"; done <<< "$cur"
      while read -r n t; do [ -n "$n" ] && ! echo "$cur" | grep -q "^$n " && printf "\r    ${M}- %s removed (%ds)${N}                             \n" "$t" "$el"; done <<< "$prev"
      prev="$cur"
    fi
    printf "\r    ⏱ %4ds   %s          " "$el" "$($label)"
    if eval "$test" || [ "$el" -ge "$timeout" ]; then break; fi
    sleep 3
  done
  WAITED=$el
  echo ""
}

# ─── Intro card ──────────────────────────────────────────────────────────────
banner "Amazon EKS Auto Mode · live demo"
clear
printf "\n\n  ${B}Amazon EKS Auto Mode: deploy pods, AWS runs the nodes${N}\n\n"
echo "  TOP:    live EC2 nodes (eks-node-viewer): type, Spot or On-Demand, CPU/memory, \$/hour"
echo "  BOTTOM: the kubectl commands, with timers measured live"
echo "  \$/hour = EC2 instance price shown by eks-node-viewer (excludes the EKS Auto Mode fee and control plane)"
echo ""
echo "  You will see: a node appear on demand, a cheaper Spot node take over,"
echo "  Graviton with no rebuild, right-sized nodes, a burst to 30 pods, and idle nodes removed."
if [ "${LIVE:-0}" = "1" ]; then
  if kubectl get nodepool cost-optimized >/dev/null 2>&1 || [ "$(node_count)" -gt 0 ]; then echo ""; echo "  Cluster is not clean. Run ./reset-demo.sh first."; exit 1; fi
fi
pause 10

# ─── 1. Zero config ─────────────────────────────────────────────────────────
header 1 "Deploy an app, get a node (nothing to install)"
watch_hint "the top pane: a node appears for the pending pods"
run "kubectl apply -f ${MANIFESTS_DIR}/01-namespace.yaml"
run "kubectl apply -f ${MANIFESTS_DIR}/02-sample-app.yaml -f ${MANIFESTS_DIR}/06-pod-disruption-budget.yaml"
lbl1() { echo "nodes: $(node_count)   pods running: $(running sample-app)/3"; }
wait_until 150 lbl1 '[ "$(running sample-app)" -ge 3 ]'
T1=$WAITED; ok "Node launched and 3 pods running in ${T1}s"
sleep 4
echo "  (nodes = kubectl get nodes with instance type, arch and Spot/On-Demand labels)"
run "nodes"
OD_TYPE=$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type 2>/dev/null | head -1)
OD_PRICE=$(price_of "$OD_TYPE"); START_COST=$(cost)
caption "You deployed an app. Auto Mode launched a node for it in ${T1}s. Nothing to install or run, not even Karpenter."
tally "1 node in ${T1}s"
pause

# ─── 2. Spot ────────────────────────────────────────────────────────────────
header 2 "One NodePool: allow Spot + On-Demand, x86 + Graviton"
watch_hint "the top pane: a Spot node joins, then the On-Demand node is drained and removed"
SNAP=$(snapshot)
run "kubectl apply -f ${MANIFESTS_DIR}/00-cost-optimized-nodepool.yaml"
lbl2() { echo "Spot nodes: $(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')   On-Demand nodes: $(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')"; }
wait_until 180 lbl2 '[ "$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d " ")" -eq 0 ] && [ "$(running sample-app)" -ge 3 ]'
T2=$WAITED; SNAP=$(snapshot)
SPOT_TYPE=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type 2>/dev/null | head -1)
sleep 3; SPOT_PRICE=$(price_of "$SPOT_TYPE")
run "nodes"
if [ "$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] && [ -n "$SPOT_TYPE" ]; then
  ok "On-Demand node replaced by Spot in ${T2}s"
  caption "No app change. Auto Mode moved the app from On-Demand ${OD_TYPE} (\$${OD_PRICE:-?}/h) to Spot ${SPOT_TYPE} (\$${SPOT_PRICE:-?}/h)."
  SWAP="On-Demand ${OD_TYPE} \$${OD_PRICE:-?}/h → Spot ${SPOT_TYPE} \$${SPOT_PRICE:-?}/h in ${T2}s"
  tally "On-Demand→Spot \$${OD_PRICE:-?}→\$${SPOT_PRICE:-?}/h"
else
  caption "Spot capacity added: $(new_nodes "$SNAP"). The On-Demand node is still draining."
  SWAP="Spot node added in ${T2}s"
fi
pause

# ─── 3. Graviton, same Deployment ───────────────────────────────────────────
header 3 "Same app, same image, now on AWS Graviton (arm64)"
watch_hint "the top pane: an arm64 node appears and the app moves to it"
report_removed "$SNAP"; SNAP=$(snapshot)
run "kubectl patch deployment sample-app -n ${NAMESPACE} -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/arch\":\"arm64\"}}}}}'"
lbl3() {
  local arm; arm=$(kubectl get nodes -l kubernetes.io/arch=arm64 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '|')
  echo "nodes: $(node_count)   app pods on arm64: $(kubectl get pods -n $NAMESPACE -l app=sample-app --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | grep -cxE "${arm:-none}")/3"
}
wait_until 180 lbl3 'kubectl rollout status deployment/sample-app -n $NAMESPACE --timeout=1s >/dev/null 2>&1'
T3=$WAITED; ok "Rollout to Graviton finished in ${T3}s"
GRAV_ON=$(placement sample-app)
run "nodes"
GRAV_TYPE=${GRAV_ON%% *}; GRAV_PRICE=$(price_of "$GRAV_TYPE")
caption "Same Deployment and image, now on ${GRAV_TYPE} Graviton (arm64) at \$${GRAV_PRICE:-?}/h, vs \$${SPOT_PRICE:-?}/h on x86 Spot. You chose arm64 with a nodeSelector; no rebuild."
tally "Graviton, same image: ${T3}s"
pause

# ─── 4. CPU-heavy ───────────────────────────────────────────────────────────
header 4 "CPU-heavy pods: 2 pods × 2 vCPU"
watch_hint "the top pane: Auto Mode picks an instance that fits 4 vCPU of requests"
report_removed "$SNAP"; SNAP=$(snapshot)
run "kubectl apply -f ${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"
lbl4() { echo "nodes: $(node_count)   pods running: $(running compute-intensive)/2"; }
wait_until 150 lbl4 '[ "$(running compute-intensive)" -ge 2 ]'
T4=$WAITED; ok "CPU pods running in ${T4}s"
NEW4=$(new_nodes "$SNAP")
run "nodes"
caption "${NEW4:+New node: ${NEW4}. }CPU pods run on: $(placement compute-intensive)."
tally "CPU pods ${T4}s"
pause

# ─── 5. Memory-heavy ────────────────────────────────────────────────────────
header 5 "Memory-heavy pods: 2 pods × 8 GiB"
watch_hint "the top pane memory bars: new capacity only if existing nodes are full"
report_removed "$SNAP"; SNAP=$(snapshot)
run "kubectl apply -f ${MANIFESTS_DIR}/04-memory-intensive-workload.yaml"
lbl5() { echo "nodes: $(node_count)   pods running: $(running memory-intensive)/2"; }
wait_until 150 lbl5 '[ "$(running memory-intensive)" -ge 2 ]'
T5=$WAITED; ok "Memory pods running in ${T5}s"
NEW5=$(new_nodes "$SNAP")
run "nodes"
caption "${NEW5:+New node: ${NEW5}. }Memory pods run on: $(placement memory-intensive)."
tally "memory pods ${T5}s"
pause

# ─── 6. Burst ───────────────────────────────────────────────────────────────
header 6 "Burst: scale the app from 3 to 30 pods"
watch_hint "the top pane: new capacity for the pending pods"
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
tally "30 pods in ${T6}s"
pause

# ─── 7. Consolidation ──────────────────────────────────────────────────────
header 7 "Scale down: Auto Mode removes nodes you no longer need"
watch_hint "the top pane: nodes go to Deleting and \$/hour drops"
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
GONE7=$(echo "$SNAP" | while read -r n t; do [ -n "$n" ] && ! snapshot </dev/null | grep -q "^$n " && echo "$t"; done | paste -sd ',' - | sed 's/,/, /g')
KEPT7=$(placement sample-app)
caption "Removed: ${GONE7:-none}. Kept: ${KEPT7} for the 3 app pods (PDBs respected). ${PEAK_COST} → ${END_COST}."
tally "${NB7}→${NA7} nodes, ${PEAK_COST}→${END_COST}"
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
printf "  %-34s %s\n" "Same 3-pod app, start:" "${START_COST} (${OD_TYPE} On-Demand)"
printf "  %-34s %s\n" "Peak, ${PEAK_NODES} nodes:" "${PEAK_COST}"
printf "  %-34s %s\n" "Same 3-pod app, end:" "${END_COST} (${KEPT7})"
awk -v a="${START_COST//[^0-9.]/}" -v b="${END_COST//[^0-9.]/}" 'BEGIN{ if (a>0) printf "  %-34s %.0f%% lower $/hour (this run)\n", "Same app, start vs end:", (1-b/a)*100 }'
echo "  \$/hour = EC2 instance price only; excludes the EKS Auto Mode fee and control plane."
echo ""
echo "  Instance choices vary run to run: Karpenter picks the cheapest fit at that moment."
pause 25
