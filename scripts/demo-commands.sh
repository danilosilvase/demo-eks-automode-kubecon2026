#!/bin/bash
# =============================================================================
# EKS Auto Mode Demo — Interactive Commands
# =============================================================================

set -e

CLUSTER_NAME="${CLUSTER_NAME:-eks-auto-demo}"
NAMESPACE="demo-app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

print_header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

wait_prompt() {
  echo ""
  read -p "  ▶ Press Enter to continue..." _
  echo ""
}

# ─── 1. Deploy a simple workload ─────────────────────────────────────────────
step_simple_workload() {
  print_header "Deploy a simple workload"

  echo ">> Creating namespace and deploying sample app (3 replicas)..."
  kubectl apply -f "${MANIFESTS_DIR}/01-namespace.yaml"
  kubectl apply -f "${MANIFESTS_DIR}/02-sample-app.yaml"

  echo ""
  echo ">> Auto Mode provisions a node automatically — watch the top pane."
  echo ">> Waiting for pods to be ready..."
  kubectl wait --for=condition=Ready pod -l app=sample-app \
    -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

  echo ""
  echo ">> Cluster state:"
  kubectl get nodes -L karpenter.sh/capacity-type,karpenter.sh/nodepool,node.kubernetes.io/instance-type
  echo ""
  kubectl get pods -n "${NAMESPACE}" -o wide

  echo ""
  echo "✓ Auto Mode provisioned a node and scheduled pods — zero config."
}

# ─── 2. Enable Spot with a custom NodePool ───────────────────────────────────
step_spot_nodepool() {
  print_header "Enable Spot with a custom NodePool"

  echo ">> Current NodePools (built-in, on-demand only):"
  kubectl get nodepools
  wait_prompt

  echo ">> Applying cost-optimized NodePool (Spot + On-Demand, weight 100)..."
  kubectl apply -f "${MANIFESTS_DIR}/00-cost-optimized-nodepool.yaml"

  echo ""
  echo ">> NodePools now:"
  kubectl get nodepools
  echo ""
  echo ">> cost-optimized config:"
  kubectl describe nodepool cost-optimized | grep -A20 "Spec:" | head -25
  wait_prompt

  echo ">> Karpenter will consolidate existing on-demand nodes to Spot."
  echo ">> Watch eks-node-viewer — nodes will transition to Spot."
  echo ""

  for i in $(seq 1 9); do
    sleep 10
    SPOT=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "   [${i}0s] Spot nodes: ${SPOT}"
    if [ "${SPOT}" -gt 0 ]; then
      echo "   ✓ Spot node detected."
      break
    fi
  done

  echo ""
  echo ">> Capacity breakdown:"
  echo "   On-Demand: $(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "   Spot:      $(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')"

  echo ""
  echo "✓ One NodePool manifest — that's all it takes to enable Spot."
}

# ─── 3. CPU-intensive workload ───────────────────────────────────────────────
step_cpu_workload() {
  print_header "CPU-intensive workload"

  echo ">> Deploying compute-intensive workload (2 CPU cores per pod, 2 replicas)..."
  kubectl apply -f "${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"

  echo ""
  echo ">> Watch eks-node-viewer — Karpenter selects a c-family instance."
  echo ">> Waiting for pods..."
  kubectl wait --for=condition=Ready pod -l app=compute-intensive \
    -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

  echo ""
  echo ">> Instance types selected:"
  kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type,\
POOL:.metadata.labels.karpenter\\.sh/nodepool

  echo ""
  echo "✓ c-family (compute-optimized) instance selected for CPU workload."
}

# ─── 4. Memory-intensive workload ────────────────────────────────────────────
step_memory_workload() {
  print_header "Memory-intensive workload"

  echo ">> Deploying memory-intensive workload (8Gi per pod, 2 replicas)..."
  kubectl apply -f "${MANIFESTS_DIR}/04-memory-intensive-workload.yaml"

  echo ""
  echo ">> Watch eks-node-viewer — Karpenter selects an r-family instance."
  echo ">> Waiting for pods..."
  kubectl wait --for=condition=Ready pod -l app=memory-intensive \
    -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

  echo ""
  echo ">> Instance types selected:"
  kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type,\
POOL:.metadata.labels.karpenter\\.sh/nodepool

  echo ""
  echo "✓ r-family (memory-optimized) instance selected for memory workload."
}

# ─── 5. Consolidation ────────────────────────────────────────────────────────
step_consolidation() {
  print_header "Consolidation"

  NODE_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  echo ">> Current nodes: ${NODE_BEFORE}"
  kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
  wait_prompt

  echo ">> Scaling down compute and memory workloads..."
  kubectl scale deployment compute-intensive --replicas=0 -n "${NAMESPACE}"
  kubectl scale deployment memory-intensive --replicas=0 -n "${NAMESPACE}"

  echo ""
  echo ">> Karpenter evaluates underutilization after 30s, then consolidates."
  echo ">> Watch eks-node-viewer — nodes will drain and disappear."

  for i in $(seq 1 12); do
    sleep 10
    CURRENT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    echo "   [${i}0s] Nodes: ${CURRENT}"
    if [ "${CURRENT}" -lt "${NODE_BEFORE}" ]; then
      echo "   ✓ Consolidation detected."
      break
    fi
  done

  echo ""
  NODE_AFTER=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  echo ">> Nodes: ${NODE_BEFORE} → ${NODE_AFTER}"
  kubectl get pods -n "${NAMESPACE}" -o wide

  echo ""
  echo "✓ Workloads consolidated to fewer nodes automatically."
}

# ─── 6. Sub-minute scaling ───────────────────────────────────────────────────
step_scaling() {
  print_header "Sub-minute scaling"

  echo ">> Current state:"
  kubectl get nodes --no-headers | wc -l | xargs -I{} echo "   Nodes: {}"
  kubectl get pods -n "${NAMESPACE}" --no-headers | wc -l | xargs -I{} echo "   Pods:  {}"
  wait_prompt

  echo ">> Scaling sample-app to 30 replicas (will exceed current node capacity)..."
  START=$(date +%s)
  kubectl scale deployment sample-app --replicas=30 -n "${NAMESPACE}"

  echo ""
  echo ">> Watch eks-node-viewer — new node provisioned in under 60 seconds."
  echo ">> Waiting for all pods to be ready..."
  kubectl wait --for=condition=Ready pod -l app=sample-app \
    -n "${NAMESPACE}" --timeout=180s 2>/dev/null || true

  END=$(date +%s)
  ELAPSED=$((END - START))

  echo ""
  echo ">> All pods ready in ${ELAPSED} seconds."
  kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
  echo ""
  kubectl get pods -n "${NAMESPACE}" --no-headers | wc -l | xargs -I{} echo "   Running pods: {}"

  echo ""
  echo "✓ Sub-minute scaling — new capacity provisioned in under 60s."
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────
step_cleanup() {
  print_header "Cleanup / Reset"

  echo ">> Resetting to initial state (3 sample-app pods)..."
  kubectl scale deployment sample-app --replicas=3 -n "${NAMESPACE}" 2>/dev/null || true
  kubectl scale deployment compute-intensive --replicas=0 -n "${NAMESPACE}" 2>/dev/null || true
  kubectl scale deployment memory-intensive --replicas=0 -n "${NAMESPACE}" 2>/dev/null || true

  echo ">> Waiting for consolidation..."
  sleep 10
  kubectl get pods -n "${NAMESPACE}"
  echo ""
  echo "✓ Reset complete."
}

# ─── Menu ────────────────────────────────────────────────────────────────────
show_menu() {
  echo ""
  echo "  ┌────────────────────────────────────────┐"
  echo "  │  EKS Auto Mode Demo                    │"
  echo "  ├────────────────────────────────────────┤"
  echo "  │  1) Simple workload                    │"
  echo "  │  2) Spot NodePool                      │"
  echo "  │  3) CPU-intensive workload             │"
  echo "  │  4) Memory-intensive workload          │"
  echo "  │  5) Consolidation                      │"
  echo "  │  6) Sub-minute scaling                 │"
  echo "  │  c) Cleanup / Reset                    │"
  echo "  │  q) Quit                               │"
  echo "  └────────────────────────────────────────┘"
  echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────
if [ -z "$1" ]; then
  while true; do
    show_menu
    read -p "  Choice: " choice
    case $choice in
      1) step_simple_workload ;;
      2) step_spot_nodepool ;;
      3) step_cpu_workload ;;
      4) step_memory_workload ;;
      5) step_consolidation ;;
      6) step_scaling ;;
      c|C) step_cleanup ;;
      q|Q) exit 0 ;;
      *) echo "  Invalid choice." ;;
    esac
  done
else
  case $1 in
    1|simple) step_simple_workload ;;
    2|spot) step_spot_nodepool ;;
    3|cpu) step_cpu_workload ;;
    4|memory) step_memory_workload ;;
    5|consolidation) step_consolidation ;;
    6|scaling) step_scaling ;;
    cleanup) step_cleanup ;;
    *) echo "Usage: $0 [1-6|cleanup]"; exit 1 ;;
  esac
fi
