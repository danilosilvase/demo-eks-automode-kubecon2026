#!/bin/bash
# =============================================================================
# EKS Auto Mode Demo — Auto-run for recording
# =============================================================================
# Usage:
#   ./scripts/demo-record.sh              # 10s pauses (default)
#   PAUSE=5 ./scripts/demo-record.sh      # faster
#   PAUSE=15 ./scripts/demo-record.sh     # slower
# =============================================================================

set -e

NAMESPACE="demo-app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"
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

# =============================================================================
echo ""
echo "  Starting demo recording in 3 seconds..."
sleep 3

# ─── 1. Zero-config provisioning ────────────────────────────────────────────
header "1. Zero-config provisioning"

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
  READY=$(kubectl get pods -n ${NAMESPACE} -l app=sample-app --no-headers 2>/dev/null | grep -c Running || echo 0)
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

echo ""
echo "  ✓ Zero config — Auto Mode handled everything."
pause

# ─── 2. Spot NodePool ───────────────────────────────────────────────────────
header "2. Enable Spot with a custom NodePool"

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

echo ""
echo "  ✓ One NodePool manifest — Spot enabled."
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
  READY=$(kubectl get pods -n ${NAMESPACE} -l app=compute-intensive --no-headers 2>/dev/null | grep -c Running || echo 0)
  printf "    [%3ds] Pods running: %s/2\n" "${ELAPSED}" "${READY}"
  if [ "${READY}" -ge 2 ]; then
    echo ""
    echo "    ✓ Compute pods ready in ${ELAPSED}s"
    break
  fi
done

pause 3
run "kubectl get nodes -o custom-columns=NAME:.metadata.name,INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type"

echo ""
echo "  ✓ c-family instance selected for CPU workload."
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
  READY=$(kubectl get pods -n ${NAMESPACE} -l app=memory-intensive --no-headers 2>/dev/null | grep -c Running || echo 0)
  printf "    [%3ds] Pods running: %s/2\n" "${ELAPSED}" "${READY}"
  if [ "${READY}" -ge 2 ]; then
    echo ""
    echo "    ✓ Memory pods ready in ${ELAPSED}s"
    break
  fi
done

pause 3
run "kubectl get nodes -o custom-columns=NAME:.metadata.name,INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type"

echo ""
echo "  ✓ r-family instance selected for memory workload."
pause

# ─── 5. Consolidation ──────────────────────────────────────────────────────
header "5. Consolidation"

NODE_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
run "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type"
pause 3

run "kubectl scale deployment compute-intensive --replicas=0 -n ${NAMESPACE}"
run "kubectl scale deployment memory-intensive --replicas=0 -n ${NAMESPACE}"

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

echo ""
echo "  ✓ Nodes: ${NODE_BEFORE} → ${NODE_AFTER}  (${TOTAL}s)"
pause

# ─── 6. Sub-minute scaling ─────────────────────────────────────────────────
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
  READY_PODS=$(kubectl get pods -n ${NAMESPACE} -l app=sample-app --no-headers 2>/dev/null | grep -c Running || echo 0)
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

echo ""
echo "  ✓ Nodes: ${NODES_BEFORE} → ${NODES_AFTER}  |  All 30 pods ready in ${TOTAL}s"
pause

# ─── Done ───────────────────────────────────────────────────────────────────
clear
echo ""
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Demo complete."
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
