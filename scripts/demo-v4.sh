#!/bin/bash
# =============================================================================
# EKS Auto Mode demo v4: follows the KubeCon NA 2026 deck
#   Core (6): 1 zero config  2 Spot  3 CPU  4 memory  5 burst  6 consolidation
#   Bonus:    g Graviton (same image on arm64; caption reports what really happened)
# Modes
#   MODE=loop (default)  booth video / recording: intro, 1-6, recap. BONUS=1 adds g before recap.
#   MODE=live            presenter menu: Enter = next step, or press 1-6, g, r (recap), c (reset), q.
# Every number shown is read live from the cluster or the eks-node-viewer pane.
# =============================================================================
set -u
NAMESPACE="demo-app"
MANIFESTS_DIR="${MANIFESTS_DIR:-manifests}"
PAUSE="${PAUSE:-12}"
MODE="${MODE:-loop}"
TSOCK="${TSOCK:-ekrec}"
TOP_PANE="${TOP_PANE:-eks-rec:0.0}"
CORE=6

G=$'\033[1;32m'; CAP=$'\033[1;97;44m'; C=$'\033[1;36m'; M=$'\033[1;35m'; B=$'\033[1m'; DIM=$'\033[2m'; Y=$'\033[1;33m'; N=$'\033[0m'

banner() { tmux -L "$TSOCK" set -g status-left " ${1} " >/dev/null 2>&1 || true; }
type_cmd() { echo ""; echo -n "  \$ "; for (( i=0; i<${#1}; i++ )); do echo -n "${1:$i:1}"; sleep 0.03; done; echo ""; sleep 0.4; }
run() { type_cmd "$1"; eval "$1"; }
pause() { [ "$MODE" = "live" ] && return 0; sleep "${1:-$PAUSE}"; }
ok() { printf "\n    ${G}✓ %s${N}\n" "$1"; }
TALLY=""
tally() {
  TALLY="${TALLY:+$TALLY  ·  }$1"
  tmux -L "$TSOCK" set -g status 2 >/dev/null 2>&1 || true
  tmux -L "$TSOCK" set -g 'status-format[1]' "#[bg=colour236,fg=colour255,bold] ${TALLY//#/##}" >/dev/null 2>&1 || true
}
tally_reset() { TALLY=""; tmux -L "$TSOCK" set -g status on >/dev/null 2>&1 || true; }
caption() { printf "\n  ${CAP} ▶ %s ${N}\n" "$1"; }
watch_hint() { printf "  ${C}Watch %s${N}\n" "$1"; }
header() { clear; banner "STEP $1/$CORE · $2"; printf "\n  ${B}%s/%s  %s${N}\n" "$1" "$CORE" "$2"; }

nodes() {
  kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type 2>/dev/null \
    | awk '{print $1, $2, $4, $6, $7, $8}' | column -t | sed 's/^/  /'
}
nodeclaims() {
  kubectl get nodeclaims -o custom-columns='NODECLAIM:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,CAPACITY:.metadata.labels.karpenter\.sh/capacity-type,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,NODEPOOL:.metadata.labels.karpenter\.sh/nodepool,READY:.status.conditions[?(@.type=="Ready")].status' 2>/dev/null | sed 's/^/  /'
}
node_count() { kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' '; }
running() { kubectl get pods -n "$NAMESPACE" -l app="$1" --no-headers 2>/dev/null | grep -c Running; }
snapshot() { kubectl get nodes --no-headers -o custom-columns=N:.metadata.name,T:.metadata.labels.node\\.kubernetes\\.io/instance-type 2>/dev/null; }
cost() { tmux -L "$TSOCK" capture-pane -p -t "$TOP_PANE" 2>/dev/null | grep -oE '\$[0-9.]+/hour' | head -1; }
price_of() { tmux -L "$TSOCK" capture-pane -p -t "$TOP_PANE" 2>/dev/null | grep -oE "${1}/\\\$[0-9.]+" | head -1 | cut -d'$' -f2; }
placement() {
  local nodes; nodes=$(kubectl get pods -n "$NAMESPACE" -l app="$1" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ')
  [ -z "${nodes// /}" ] && return 0
  # shellcheck disable=SC2086
  kubectl get nodes $nodes --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type,A:.metadata.labels.kubernetes\\.io/arch,C:.metadata.labels.karpenter\\.sh/capacity-type \
    | awk '{print $1" "$2" "$3}' | sort -u | paste -sd ',' - | sed 's/,/, /g'
}
report_removed() {
  local before="$1" now gone
  now=$(snapshot | awk '{print $1}')
  gone=$(echo "$before" | while read -r n t; do [ -n "$n" ] && ! echo "$now" | grep -qx "$n" && echo "$t"; done | paste -sd ',' - | sed 's/,/, /g')
  [ -n "$gone" ] && printf "  ${M}↺ Since the last step Auto Mode removed node(s) no longer needed: %s${N}\n" "$gone"
}
new_nodes() {
  local before="$1" names=""
  for n in $(snapshot | awk '{print $1}'); do echo "$before" | awk '{print $1}' | grep -qx "$n" || names="$names $n"; done
  [ -z "${names// /}" ] && return 0
  # shellcheck disable=SC2086
  kubectl get nodes $names --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type,A:.metadata.labels.kubernetes\\.io/arch,C:.metadata.labels.karpenter\\.sh/capacity-type \
    | while read -r t a c; do echo "$t $a $c \$$(price_of "$t" </dev/null)/h"; done | paste -sd ',' - | sed 's/,/, /g'
}
# Seconds from NodeClaim created (Auto Mode decided) to node Ready, for NodeClaims created after epoch $1.
# Prints the slowest one, so the claim on screen is never better than reality.
ready_secs() {
  kubectl get nodeclaims -o json 2>/dev/null | /usr/bin/python3 -c '
import json,sys,datetime
since=int(sys.argv[1]); p=lambda s: datetime.datetime.strptime(s,"%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
out=[]
for i in json.load(sys.stdin).get("items",[]):
    c=p(i["metadata"]["creationTimestamp"])
    if c < since-5: continue
    r=[x for x in i.get("status",{}).get("conditions",[]) if x.get("type")=="Ready" and x.get("status")=="True"]
    if r: out.append(int(p(r[0]["lastTransitionTime"])-c))
print(max(out) if out else "")' "$1"
}
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
have_app() { kubectl get deployment sample-app -n "$NAMESPACE" >/dev/null 2>&1; }
need_app() { have_app && return 0; printf "\n  ${Y}Run step 1 first (no app deployed yet).${N}\n"; return 1; }

# ─── Intro ──────────────────────────────────────────────────────────────────
intro() {
  banner "Amazon EKS Auto Mode · cost optimization demo"
  clear
  printf "\n\n  ${B}Amazon EKS Auto Mode: you deploy pods, AWS runs the nodes${N}\n\n"
  echo "  TOP:    live EC2 nodes (eks-node-viewer): type, Spot or On-Demand, CPU/memory, \$/hour"
  echo "  BOTTOM: the kubectl commands, with timers measured live"
  echo "  \$/hour = EC2 instance price shown by eks-node-viewer (excludes the EKS Auto Mode fee and control plane)"
  echo ""
  echo "  You will see: zero config, Spot, right-sized nodes for CPU and memory,"
  echo "  a burst to 30 pods, and consolidation removing nodes you no longer need."
}

# ─── 1. Zero config: pending pod → Auto Mode evaluates → node ready ─────────
step1() {
  header 1 "Zero config: deploy an app, Auto Mode adds the node"
  watch_hint "the top pane: a node appears for the pending pods"
  S1_EPOCH=$(date +%s)
  run "kubectl apply -f ${MANIFESTS_DIR}/01-namespace.yaml"
  run "kubectl apply -f ${MANIFESTS_DIR}/02-sample-app.yaml -f ${MANIFESTS_DIR}/06-pod-disruption-budget.yaml"
  sleep 2
  run "kubectl get pods -n ${NAMESPACE}"
  echo "  Pending pods: no node fits them yet. Auto Mode reads their requests and picks an instance."
  lbl1() { echo "nodes: $(node_count)   pods running: $(running sample-app)/3"; }
  wait_until 150 lbl1 '[ "$(running sample-app)" -ge 3 ]'
  T1=$WAITED; R1=$(ready_secs "$S1_EPOCH")
  ok "Node launched and 3 pods running in ${T1}s${R1:+ (node Ready ${R1}s after Auto Mode chose it)}"
  sleep 3
  run "nodeclaims"
  echo "  NodeClaim = Auto Mode's decision: which instance, Spot or On-Demand, which zone."
  OD_TYPE=$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type 2>/dev/null | head -1)
  OD_PRICE=$(price_of "$OD_TYPE"); START_COST=$(cost)
  caption "Pending pod → Auto Mode evaluates → node ready. ${OD_TYPE:-A node} in ${T1}s, nothing installed, not even Karpenter."
  tally "1 node in ${T1}s"
  NEXT=2
}

# ─── 2. Spot ────────────────────────────────────────────────────────────────
step2() {
  need_app || return 0
  header 2 "Spot: one NodePool allows Spot + On-Demand"
  watch_hint "the top pane: a Spot node joins, then the On-Demand node is drained and removed"
  SNAP=$(snapshot)
  run "kubectl apply -f ${MANIFESTS_DIR}/00-cost-optimized-nodepool.yaml"
  echo "  The NodePool allows Spot and On-Demand, x86 and Graviton. Auto Mode picks the cheapest fit."
  lbl2() { echo "Spot nodes: $(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')   On-Demand nodes: $(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')"; }
  wait_until 180 lbl2 '[ "$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d " ")" -eq 0 ] && [ "$(running sample-app)" -ge 3 ]'
  T2=$WAITED; SNAP=$(snapshot)
  SPOT_TYPE=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers -o custom-columns=T:.metadata.labels.node\\.kubernetes\\.io/instance-type 2>/dev/null | head -1)
  sleep 3; SPOT_PRICE=$(price_of "$SPOT_TYPE")
  run "nodes"
  if [ "$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] && [ -n "$SPOT_TYPE" ]; then
    ok "On-Demand node replaced by Spot in ${T2}s"
    caption "No app change. Auto Mode moved the app from On-Demand ${OD_TYPE:-?} (\$${OD_PRICE:-?}/h) to Spot ${SPOT_TYPE} (\$${SPOT_PRICE:-?}/h). No interruption handler to write."
    SWAP="On-Demand ${OD_TYPE:-?} \$${OD_PRICE:-?}/h → Spot ${SPOT_TYPE} \$${SPOT_PRICE:-?}/h in ${T2}s"
    tally "On-Demand→Spot \$${OD_PRICE:-?}→\$${SPOT_PRICE:-?}/h"
  else
    caption "Spot capacity added: $(new_nodes "$SNAP"). The On-Demand node is still draining."
    SWAP="Spot node added in ${T2}s"
    tally "Spot added in ${T2}s"
  fi
  NEXT=3
}

# ─── 3. CPU-heavy ───────────────────────────────────────────────────────────
step3() {
  need_app || return 0
  header 3 "Right-sized for CPU: 2 pods × 2 vCPU"
  watch_hint "the top pane: Auto Mode picks an instance that fits 4 vCPU of requests"
  report_removed "${SNAP:-}"; SNAP=$(snapshot); E=$(date +%s)
  run "kubectl apply -f ${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"
  lbl3() { echo "nodes: $(node_count)   pods running: $(running compute-intensive)/2"; }
  wait_until 150 lbl3 '[ "$(running compute-intensive)" -ge 2 ]'
  T3=$WAITED; R3=$(ready_secs "$E"); NEW3=$(new_nodes "$SNAP"); P3=$(placement compute-intensive)
  ok "CPU pods running in ${T3}s${R3:+ (new node Ready ${R3}s after Auto Mode chose it)}"
  run "nodes"
  caption "${NEW3:+New node: ${NEW3}. }CPU pods run on: ${P3}. No node group for this workload."
  tally "CPU pods ${T3}s"
  NEXT=4
}

# ─── 4. Memory-heavy ────────────────────────────────────────────────────────
step4() {
  need_app || return 0
  header 4 "Right-sized for memory: 2 pods × 8 GiB"
  watch_hint "the top pane memory bars: new capacity only if existing nodes are full"
  report_removed "${SNAP:-}"; SNAP=$(snapshot); E=$(date +%s)
  run "kubectl apply -f ${MANIFESTS_DIR}/04-memory-intensive-workload.yaml"
  lbl4() { echo "nodes: $(node_count)   pods running: $(running memory-intensive)/2"; }
  wait_until 150 lbl4 '[ "$(running memory-intensive)" -ge 2 ]'
  T4=$WAITED; R4=$(ready_secs "$E"); NEW4=$(new_nodes "$SNAP"); P4=$(placement memory-intensive)
  ok "Memory pods running in ${T4}s${R4:+ (new node Ready ${R4}s after Auto Mode chose it)}"
  run "nodes"
  caption "${NEW4:+New node: ${NEW4}. }Memory pods run on: ${P4}. Same NodePool, different instance."
  tally "memory pods ${T4}s"
  NEXT=5
}

# ─── 5. Burst ───────────────────────────────────────────────────────────────
step5() {
  need_app || return 0
  header 5 "Burst: scale the app from 3 to 30 pods"
  watch_hint "the top pane: new capacity for the pending pods"
  report_removed "${SNAP:-}"; SNAP=$(snapshot); E=$(date +%s)
  NB5=$(node_count)
  run "kubectl scale deployment sample-app -n ${NAMESPACE} --replicas=30"
  lbl5() { echo "nodes: $(node_count)   pods running: $(running sample-app)/30"; }
  wait_until 240 lbl5 '[ "$(running sample-app)" -ge 30 ]'
  T5=$WAITED; NA5=$(node_count); R5=$(ready_secs "$E")
  SUFFIX=""; [ "$T5" -lt 60 ] && SUFFIX=" (under a minute)"
  ok "30 pods running in ${T5}s${SUFFIX}${R5:+, new node Ready ${R5}s after Auto Mode chose it}"
  sleep 4; PEAK_COST=$(cost); PEAK_NODES=$(node_count)
  run "nodes"
  caption "30 pods: ${NB5} → ${NA5} nodes, all running in ${T5}s${SUFFIX}. Cluster now ${PEAK_COST}."
  tally "30 pods in ${T5}s"
  NEXT=6
}

# ─── 6. Consolidation ───────────────────────────────────────────────────────
step6() {
  need_app || return 0
  header 6 "Consolidation: Auto Mode removes nodes you no longer need"
  watch_hint "the top pane: nodes go to Deleting and \$/hour drops"
  SNAP=$(snapshot); NB6=$(node_count); [ -z "${PEAK_COST:-}" ] && PEAK_COST=$(cost)
  run "kubectl scale deployment compute-intensive memory-intensive -n ${NAMESPACE} --replicas=0"
  run "kubectl scale deployment sample-app -n ${NAMESPACE} --replicas=3"
  echo "  Demo NodePool: consolidationPolicy WhenEmptyOrUnderutilized, consolidateAfter 30s."
  echo "  (Auto Mode's built-in NodePools use Balanced: same idea, skips moves that disrupt more than they save.)"
  lbl6() { echo "nodes: $(node_count)   cluster cost: $(cost)"; }
  wait_until 240 lbl6 '[ "$(node_count)" -le 1 ]'
  T6=$WAITED; NA6=$(node_count)
  sleep 4; END_COST=$(cost)
  ok "${NB6} → ${NA6} node(s) in ${T6}s"
  run "nodes"
  GONE6=$(echo "$SNAP" | while read -r n t; do [ -n "$n" ] && ! snapshot </dev/null | grep -q "^$n " && echo "$t"; done | paste -sd ',' - | sed 's/,/, /g')
  KEPT6=$(placement sample-app)
  caption "Removed: ${GONE6:-none}. Kept: ${KEPT6} for the 3 app pods (PDBs respected). ${PEAK_COST} → ${END_COST}."
  tally "${NB6}→${NA6} nodes, ${PEAK_COST}→${END_COST}"
  SNAP=$(snapshot)
  NEXT=r
}

# ─── g. Bonus: Graviton, same image ─────────────────────────────────────────
stepg() {
  need_app || return 0
  clear; banner "BONUS · Graviton: same image on arm64"
  printf "\n  ${B}Bonus  Graviton: same app, same image, on arm64${N}\n"
  watch_hint "the top pane: the app's node and its arm64/amd64 label"
  report_removed "${SNAP:-}"; SNAP=$(snapshot); E=$(date +%s)
  local before; before=$(placement sample-app)
  echo "  App now runs on: ${before:-?}"
  run "kubectl patch deployment sample-app -n ${NAMESPACE} -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/arch\":\"arm64\"}}}}}'"
  lblg() {
    local arm; arm=$(kubectl get nodes -l kubernetes.io/arch=arm64 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '|')
    local want; want=$(kubectl get deployment sample-app -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null)
    echo "nodes: $(node_count)   app pods on arm64: $(kubectl get pods -n $NAMESPACE -l app=sample-app --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | grep -cxE "${arm:-none}")/${want:-?}"
  }
  wait_until 180 lblg 'kubectl rollout status deployment/sample-app -n $NAMESPACE --timeout=1s >/dev/null 2>&1'
  TG=$WAITED; RG=$(ready_secs "$E"); NEWG=$(new_nodes "$SNAP")
  GRAV_ON=$(placement sample-app); GRAV_TYPE=${GRAV_ON%% *}; GRAV_PRICE=$(price_of "$GRAV_TYPE")
  ok "Rollout to arm64 finished in ${TG}s"
  run "nodes"
  if [ -n "$NEWG" ] && echo "$NEWG" | grep -q arm64; then
    caption "Auto Mode launched Graviton ${GRAV_TYPE} (\$${GRAV_PRICE:-?}/h)${RG:+, Ready ${RG}s after it chose it}. Same Deployment, same multi-arch image, no rebuild."
  else
    caption "Already had a Graviton node (${GRAV_TYPE}, \$${GRAV_PRICE:-?}/h), so no new node: the pods moved onto it. Same image, no rebuild."
  fi
  tally "Graviton, same image: ${TG}s"
  GRAV_DONE=1
  NEXT=r
}

# ─── Recap ──────────────────────────────────────────────────────────────────
recap() {
  banner "Amazon EKS Auto Mode · results from this run"
  clear
  printf "\n\n  ${B}Measured in this run${N}\n\n"
  [ -n "${T1:-}" ] && printf "  %-34s %s\n" "Zero config, first node + 3 pods:" "${T1}s, nothing installed"
  [ -n "${SWAP:-}" ] && printf "  %-34s %s\n" "Spot:" "${SWAP}"
  [ -n "${T3:-}" ] && printf "  %-34s %s\n" "CPU pods (right-sized):" "${T3}s, on ${P3}"
  [ -n "${T4:-}" ] && printf "  %-34s %s\n" "Memory pods (right-sized):" "${T4}s, on ${P4}"
  [ -n "${T5:-}" ] && printf "  %-34s %s\n" "Burst to 30 pods:" "${T5}s, ${NB5} → ${NA5} nodes"
  [ -n "${T6:-}" ] && printf "  %-34s %s\n" "Consolidation:" "${NB6} → ${NA6} node(s) in ${T6}s"
  [ -n "${GRAV_DONE:-}" ] && printf "  %-34s %s\n" "Graviton, same image:" "${TG}s rollout, ${GRAV_ON}"
  echo ""
  if [ -n "${START_COST:-}" ] && [ -n "${END_COST:-}" ]; then
    printf "  %-34s %s\n" "Same 3-pod app, start:" "${START_COST} (${OD_TYPE:-?} On-Demand)"
    [ -n "${PEAK_COST:-}" ] && printf "  %-34s %s\n" "Peak, ${PEAK_NODES:-?} nodes:" "${PEAK_COST}"
    printf "  %-34s %s\n" "Same 3-pod app, end:" "${END_COST} (${KEPT6:-?})"
    awk -v a="${START_COST//[^0-9.]/}" -v b="${END_COST//[^0-9.]/}" 'BEGIN{ if (a>0) printf "  %-34s %.0f%% lower $/hour (this run)\n", "Same app, start vs end:", (1-b/a)*100 }'
  fi
  echo "  \$/hour = EC2 instance price only; excludes the EKS Auto Mode fee and control plane."
  echo ""
  echo "  Instance choices vary run to run: Auto Mode picks the cheapest fit at that moment."
  NEXT=c
}

# ─── Reset (live menu) ──────────────────────────────────────────────────────
reset_cluster() {
  clear; banner "Resetting the demo"
  printf "\n  Removing the demo app and NodePool; Auto Mode then removes the nodes.\n\n"
  kubectl --request-timeout=20s delete namespace "$NAMESPACE" --wait=false --ignore-not-found
  kubectl --request-timeout=20s delete nodepool cost-optimized --ignore-not-found
  lblc() { echo "nodes: $(node_count)"; }
  wait_until 300 lblc '[ "$(node_count)" -eq 0 ] && ! kubectl get ns '"$NAMESPACE"' >/dev/null 2>&1'
  unset P3 P4 T1 T3 T4 T5 T6 TG SWAP START_COST PEAK_COST END_COST GRAV_DONE SNAP
  tally_reset
  ok "Clean: 0 nodes. Ready for step 1."
  NEXT=1
}

clean_or_exit() {
  if kubectl get nodepool cost-optimized >/dev/null 2>&1 || [ "$(node_count)" -gt 0 ]; then
    echo ""; echo "  Cluster is not clean. Run ./reset-demo.sh first."; exit 1
  fi
}

# ─── Main ───────────────────────────────────────────────────────────────────
NEXT=1
if [ "$MODE" = "live" ]; then
  intro
  have_app && printf "\n  ${Y}Demo app already deployed. Press c to reset, or continue from any step.${N}\n"
  while true; do
    printf "\n  ${DIM}1 zero-config  2 spot  3 cpu  4 memory  5 burst  6 consolidate  g graviton  r recap  c reset  q quit${N}"
    printf "\n  ${B}[Enter] = %s${N}  > " "$NEXT"
    while read -r -t 0.05 _; do :; done
    read -r key; key="${key:-$NEXT}"
    case "$key" in
      1) step1 ;; 2) step2 ;; 3) step3 ;; 4) step4 ;; 5) step5 ;; 6) step6 ;;
      g|G) stepg ;; r|R) recap ;; c|C) reset_cluster ;; q|Q) exit 0 ;;
      *) echo "  ? use 1-6, g, r, c or q" ;;
    esac
  done
else
  clean_or_exit
  intro; pause 10
  step1; pause
  step2; pause
  step3; pause
  step4; pause
  step5; pause
  step6; pause
  [ "${BONUS:-0}" = "1" ] && { stepg; pause; }
  recap; pause 25
fi
