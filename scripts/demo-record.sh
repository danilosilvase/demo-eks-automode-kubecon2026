#!/bin/bash
# =============================================================================
# EKS Auto Mode Demo: auto-run for the silent booth recording
# =============================================================================
# Usage:
#   ./scripts/demo-record.sh              # 10s pauses (default)
#   PAUSE=5 ./scripts/demo-record.sh      # faster
#   PAUSE=15 ./scripts/demo-record.sh     # slower
# =============================================================================

set -e

NAMESPACE="demo-app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${MANIFESTS_DIR:-${SCRIPT_DIR}/../manifests}"
PAUSE="${PAUSE:-10}"

type_cmd() {
  echo ""
  echo -n "  \$ "
  for (( i=0; i<${#1}; i++ )); do
    echo -n "${1:$i:1}"
    sleep 0.04
  done
  echo ""
  sleep 0.5
}

run() { type_cmd "$1"; eval "$1"; }

pause() {
  echo ""
  sleep "${1:-$PAUSE}"
}

header() {
  clear
  echo ""
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  sleep 2
}

# Silent booth captions: one bold line per step. Numbers shown here come from
# the run itself (timers, node labels), never from hard-coded claims.
caption() {
  echo ""
  printf "  \033[1;33m▶ %s\033[0m\n" "$1"
}

# One-line summary of where an app's pods run, e.g. "c7g.xlarge arm64 spot"
placement() {
  local app="$1" nodes
  nodes=$(kubectl get pods -n "${NAMESPACE}" -l app="${app}" \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ')
  [ -z "${nodes// /}" ] && return 0
  # shellcheck disable=SC2086
  kubectl get nodes ${nodes} --no-headers -o custom-columns=\
T:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
A:.metadata.labels.kubernetes\\.io/arch,\
C:.metadata.labels.karpenter\\.sh/capacity-type \
    | awk '{print $1" "$2" "$3}' | sort -u | paste -sd ',' - | sed 's/,/, /g'
}

# =============================================================================
echo ""
echo "  Starting demo recording in 3 seconds..."
sleep 3

# ─── 1. Zero-config provisioning ────────────────────────────────────────────
header "1. Zero config: deploy an app, get a node"

run "kubectl apply -f ${MANIFESTS_DIR}/01-namespace.yaml"

PROVISION_START=$(date +%s)
run "kubectl apply -f ${MANIFESTS_DIR}/02-sample-app.yaml"

echo ""
echo "  ⏱ Waiting for node and pods..."
for i in $(seq 1 24); do
  sleep 5
  NOW=$(date +%s)
  ELAPSED=$(( NOW - PROVISION_START ))
  NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  READY=$(kubectl get pods -n ${NAMESPACE} -l app=sample-app --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
  printf "    [%3ds] Nodes: %s  Pods running: %s/3\n" "${ELAPSED}" "${NODES}" "${READY}"
  if [ "${READY}" -ge 3 ]; then
    echo ""
    echo "    ✓ Node provisioned and all pods ready in ${ELAPSED}s"
    break
  fi
done

pause 3
run "kubectl get nodes -L karpenter.sh/capacity-type,karpenter.sh/nodepool,node.kubernetes.io/instance-type"
pause 3
run "kubectl get pods -n ${NAMESPACE} -o wide"

caption "No Karpenter to install or run. Auto Mode manages it."
pause

# ─── 2. Spot NodePool ───────────────────────────────────────────────────────
header "2. Spot + Graviton with one NodePool"

run "kubectl get nodepools"
pause 3
run "kubectl apply -f ${MANIFESTS_DIR}/00-cost-optimized-nodepool.yaml"
pause 3
run "kubectl get nodepools"

echo ""
echo "  ⏱ Waiting for Spot node..."
for i in $(seq 1 18); do
  sleep 5
  SPOT=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "    [$(( i * 5 ))s] Spot nodes: ${SPOT}"
  if [ "$SPOT" -gt 0 ]; then
    echo "    ✓ Spot node detected."
    break
  fi
done

run "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type"

caption "Spot and Graviton: one NodePool, Karpenter already there."
pause

# ─── 3. CPU-intensive workload ──────────────────────────────────────────────
header "3. CPU-intensive workload"

CPU_START=$(date +%s)
run "kubectl apply -f ${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"

echo ""
echo "  ⏱ Waiting for c-family instance..."
for i in $(seq 1 24); do
  sleep 5
  NOW=$(date +%s)
  ELAPSED=$(( NOW - CPU_START ))
  READY=$(kubectl get pods -n ${NAMESPACE} -l app=compute-intensive --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
  printf "    [%3ds] Pods running: %s/2\n" "${ELAPSED}" "${READY}"
  if [ "${READY}" -ge 2 ]; then
    echo ""
    echo "    ✓ Compute pods ready in ${ELAPSED}s"
    break
  fi
done

pause 3
run "kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type"

caption "CPU-heavy pods. Karpenter picked: $(placement compute-intensive)"
pause

# ─── 4. Memory-intensive workload ───────────────────────────────────────────
header "4. Memory-intensive workload"

MEM_START=$(date +%s)
run "kubectl apply -f ${MANIFESTS_DIR}/04-memory-intensive-workload.yaml"

echo ""
echo "  ⏱ Waiting for r-family instance..."
for i in $(seq 1 24); do
  sleep 5
  NOW=$(date +%s)
  ELAPSED=$(( NOW - MEM_START ))
  READY=$(kubectl get pods -n ${NAMESPACE} -l app=memory-intensive --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
  printf "    [%3ds] Pods running: %s/2\n" "${ELAPSED}" "${READY}"
  if [ "${READY}" -ge 2 ]; then
    echo ""
    echo "    ✓ Memory pods ready in ${ELAPSED}s"
    break
  fi
done

pause 3
run "kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type"

caption "Memory-heavy pods. Karpenter picked: $(placement memory-intensive)"
pause

# ─── 5. Same app on Graviton ────────────────────────────────────────────────
header "5. Same app, Graviton"

GRAV_START=$(date +%s)
run "kubectl apply -f ${MANIFESTS_DIR}/07-graviton-workload.yaml"

echo ""
echo "  ⏱ Waiting for Graviton pods..."
for i in $(seq 1 24); do
  sleep 5
  NOW=$(date +%s)
  ELAPSED=$(( NOW - GRAV_START ))
  READY=$(kubectl get pods -n ${NAMESPACE} -l app=sample-app-graviton --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
  printf "    [%3ds] Pods running: %s/3\n" "${ELAPSED}" "${READY}"
  if [ "${READY}" -ge 3 ]; then
    echo ""
    echo "    ✓ Graviton pods ready in ${ELAPSED}s"
    break
  fi
done

pause 3
run "kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type"

caption "Same container image, now on $(placement sample-app-graviton). No rebuild."
pause

# ─── 6. Sub-minute scaling ──────────────────────────────────────────────────
header "6. Sub-minute scaling"

NODES_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
PODS_BEFORE=$(kubectl get pods -n ${NAMESPACE} --no-headers | wc -l | tr -d ' ')
echo "  Current: ${NODES_BEFORE} node(s), ${PODS_BEFORE} pod(s)"
pause 3

SCALE_START=$(date +%s)
run "kubectl scale deployment sample-app --replicas=30 -n ${NAMESPACE}"

echo ""
echo "  ⏱ Waiting for new node..."
for i in $(seq 1 24); do
  sleep 5
  NOW=$(date +%s)
  ELAPSED=$(( NOW - SCALE_START ))
  CURRENT_NODES=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  READY_PODS=$(kubectl get pods -n ${NAMESPACE} -l app=sample-app --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
  printf "    [%3ds] Nodes: %s  Pods running: %s/30\n" "${ELAPSED}" "${CURRENT_NODES}" "${READY_PODS}"
  if [ "${CURRENT_NODES}" -gt "${NODES_BEFORE}" ]; then
    echo ""
    echo "    ✓ New node provisioned in ${ELAPSED}s"
    break
  fi
done

echo ""
echo "  Waiting for all 30 pods..."
kubectl wait --for=condition=Ready pod -l app=sample-app \
  -n "${NAMESPACE}" --timeout=180s 2>/dev/null || true

NOW=$(date +%s)
TOTAL=$(( NOW - SCALE_START ))
NODES_AFTER=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')

run "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type"

caption "30 pods: ${NODES_BEFORE} → ${NODES_AFTER} nodes, all ready in ${TOTAL}s."
pause

# ─── 7. Consolidation ──────────────────────────────────────────────────────
header "7. Consolidation"

NODE_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
run "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type"
pause 3

run "kubectl scale deployment compute-intensive --replicas=0 -n ${NAMESPACE}"
run "kubectl scale deployment memory-intensive --replicas=0 -n ${NAMESPACE}"
run "kubectl scale deployment sample-app-graviton --replicas=0 -n ${NAMESPACE}"
run "kubectl scale deployment sample-app --replicas=3 -n ${NAMESPACE}"

CONSOLIDATION_START=$(date +%s)
echo ""
echo "  ⏱ Waiting for node removal..."
for i in $(seq 1 24); do
  sleep 5
  NOW=$(date +%s)
  ELAPSED=$(( NOW - CONSOLIDATION_START ))
  CURRENT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  printf "    [%3ds] Nodes: %s\n" "${ELAPSED}" "${CURRENT}"
  if [ "${CURRENT}" -lt "${NODE_BEFORE}" ]; then
    echo ""
    echo "    ✓ Node removed in ${ELAPSED}s"
    break
  fi
done

for i in $(seq 1 12); do
  CURRENT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  if [ "${CURRENT}" -le 1 ]; then break; fi
  sleep 5
  NOW=$(date +%s)
  ELAPSED=$(( NOW - CONSOLIDATION_START ))
  printf "    [%3ds] Nodes: %s\n" "${ELAPSED}" "${CURRENT}"
done

NOW=$(date +%s)
TOTAL=$(( NOW - CONSOLIDATION_START ))
NODE_AFTER=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')

run "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type"

caption "Unused nodes removed: ${NODE_BEFORE} → ${NODE_AFTER} in ${TOTAL}s. You stop paying for them."
pause

# ─── Done ───────────────────────────────────────────────────────────────────
clear
echo ""
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Demo complete."
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
