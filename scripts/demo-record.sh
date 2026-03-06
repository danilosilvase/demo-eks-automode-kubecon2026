#!/bin/bash
# =============================================================================
# EKS Auto Mode Demo — Auto-run for recording
# =============================================================================
# Runs all demo steps sequentially with pauses between them.
# Start your screen recording, then run this script.
#
# Usage:
#   ./scripts/demo-record.sh              # default pauses
#   PAUSE=5 ./scripts/demo-record.sh      # faster (5s between steps)
#   PAUSE=15 ./scripts/demo-record.sh     # slower (15s between steps)
# =============================================================================

set -e

NAMESPACE="demo-app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"
PAUSE="${PAUSE:-10}"

# Simulates typing a command for the recording
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

# Run a command with simulated typing
run() {
  type_cmd "$1"
  eval "$1"
}

pause() {
  echo ""
  echo "  ─── pausing ${1:-$PAUSE}s ───"
  sleep "${1:-$PAUSE}"
}

header() {
  echo ""
  echo ""
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  sleep 2
}

wait_nodes() {
  local target=$1
  local max=$2
  for i in $(seq 1 "$max"); do
    sleep 5
    NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$NODES" -ge "$target" ] 2>/dev/null; then break; fi
  done
}

wait_fewer_nodes() {
  local target=$1
  local max=$2
  for i in $(seq 1 "$max"); do
    sleep 10
    NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "    nodes: ${NODES}"
    if [ "$NODES" -le "$target" ] 2>/dev/null; then break; fi
  done
}

# =============================================================================
echo ""
echo "  Starting EKS Auto Mode demo recording in 3 seconds..."
sleep 3

# ─── Step 1: Simple workload ────────────────────────────────────────────────
header "1. Deploy a simple workload"

run "kubectl apply -f ${MANIFESTS_DIR}/01-namespace.yaml"
run "kubectl apply -f ${MANIFESTS_DIR}/02-sample-app.yaml"

echo ""
echo "  Waiting for node and pods..."
kubectl wait --for=condition=Ready pod -l app=sample-app \
  -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

pause 3

run "kubectl get nodes -L karpenter.sh/capacity-type,karpenter.sh/nodepool,node.kubernetes.io/instance-type"

pause 3

run "kubectl get pods -n ${NAMESPACE} -o wide"

echo ""
echo "  ✓ Auto Mode provisioned a node and scheduled pods — zero config."
pause

# ─── Step 2: Spot NodePool ──────────────────────────────────────────────────
header "2. Enable Spot with a custom NodePool"

run "kubectl get nodepools"

pause 3

run "kubectl apply -f ${MANIFESTS_DIR}/00-cost-optimized-nodepool.yaml"

pause 3

run "kubectl get nodepools"

echo ""
echo "  Waiting for Spot node..."
for i in $(seq 1 18); do
  sleep 5
  SPOT=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$SPOT" -gt 0 ]; then break; fi
done

run "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type"

echo ""
echo "  ✓ One NodePool manifest — Spot enabled."
pause

# ─── Step 3: CPU-intensive workload ─────────────────────────────────────────
header "3. CPU-intensive workload"

run "kubectl apply -f ${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"

echo ""
echo "  Waiting for compute pods..."
kubectl wait --for=condition=Ready pod -l app=compute-intensive \
  -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

pause 3

run "kubectl get nodes -o custom-columns=NAME:.metadata.name,INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type"

echo ""
echo "  ✓ c-family instance selected for CPU workload."
pause

# ─── Step 4: Memory-intensive workload ──────────────────────────────────────
header "4. Memory-intensive workload"

run "kubectl apply -f ${MANIFESTS_DIR}/04-memory-intensive-workload.yaml"

echo ""
echo "  Waiting for memory pods..."
kubectl wait --for=condition=Ready pod -l app=memory-intensive \
  -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

pause 3

run "kubectl get nodes -o custom-columns=NAME:.metadata.name,INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type"

echo ""
echo "  ✓ r-family instance selected for memory workload."
pause

# ─── Step 5: Consolidation ──────────────────────────────────────────────────
header "5. Consolidation"

NODE_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
run "kubectl get nodes"

pause 3

echo ""
echo "  Scaling down compute and memory workloads..."
run "kubectl scale deployment compute-intensive --replicas=0 -n ${NAMESPACE}"
run "kubectl scale deployment memory-intensive --replicas=0 -n ${NAMESPACE}"

echo ""
echo "  Waiting for consolidation..."
wait_fewer_nodes 1 18

run "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type"

NODE_AFTER=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
echo ""
echo "  ✓ Nodes: ${NODE_BEFORE} → ${NODE_AFTER}"
pause

# ─── Step 6: Sub-minute scaling ─────────────────────────────────────────────
header "6. Sub-minute scaling"

run "kubectl get nodes --no-headers | wc -l"
run "kubectl get pods -n ${NAMESPACE} --no-headers | wc -l"

pause 3

echo ""
START=$(date +%s)
run "kubectl scale deployment sample-app --replicas=30 -n ${NAMESPACE}"

echo ""
echo "  Waiting for all pods..."
kubectl wait --for=condition=Ready pod -l app=sample-app \
  -n "${NAMESPACE}" --timeout=180s 2>/dev/null || true

END=$(date +%s)
ELAPSED=$((END - START))

pause 3

run "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type"

echo ""
echo "  ✓ All pods ready in ${ELAPSED} seconds."
pause

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo ""
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Demo complete."
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
