#!/bin/bash
# =============================================================================
# EKS Auto Mode Demo — Step-by-Step Commands
# =============================================================================
# Run individual demo parts from the command terminal pane.
# The visual tools (eks-node-viewer, k9s, CloudWatch) update automatically.
#
# Usage:
#   ./scripts/demo-commands.sh part1|part2|part3|part4|cleanup
#   ./scripts/demo-commands.sh          # interactive menu
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

# ─── Part 1: Initial State & Spot Integration ────────────────────────────────
part1() {
  print_header "PART 1: Initial State & Spot Integration (2-3 min)"

  echo ">> Current nodes (capacity type + instance type):"
  kubectl get nodes -L karpenter.sh/capacity-type,karpenter.sh/nodepool,node.kubernetes.io/instance-type -o wide
  wait_prompt

  echo ">> Pods in ${NAMESPACE}:"
  kubectl get pods -n "${NAMESPACE}" -o wide
  wait_prompt

  echo ">> NodePools — notice the custom 'cost-optimized' pool with Spot:"
  kubectl get nodepools
  echo ""
  echo ">> cost-optimized NodePool config (Spot + On-Demand):"
  kubectl describe nodepool cost-optimized | head -45
  wait_prompt

  echo ">> Capacity type breakdown:"
  echo "   On-Demand: $(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "   Spot:      $(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')"

  echo ""
  echo "✓ Part 1 complete. Watch eks-node-viewer (top pane) for Spot vs On-Demand."
}

# ─── Part 2: Intelligent Instance Selection ──────────────────────────────────
part2() {
  print_header "PART 2: Intelligent Instance Selection (3-4 min)"

  echo ">> Deploying compute-intensive workload (2 CPU cores per pod)..."
  kubectl apply -f "${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"

  echo ""
  echo ">> Watch eks-node-viewer (top pane) for new node provisioning..."
  echo ">> Watch k9s (bottom-left) for pods transitioning Pending → Running..."
  echo ""
  echo ">> Waiting for pods to be ready (timeout 120s)..."
  kubectl wait --for=condition=Ready pod -l app=compute-intensive \
    -n "${NAMESPACE}" --timeout=120s 2>/dev/null || \
    echo "   (some pods may still be starting)"

  echo ""
  echo ">> Pod distribution across nodes:"
  kubectl get pods -n "${NAMESPACE}" -o wide
  echo ""
  echo ">> Node instance types selected by Auto Mode:"
  kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type,\
AGE:.metadata.creationTimestamp

  echo ""
  echo "✓ Part 2 complete. Note the instance type Auto Mode selected."
}

# ─── Part 3: Continuous Consolidation ────────────────────────────────────────
part3() {
  print_header "PART 3: Continuous Consolidation (4-5 min)"

  NODE_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  echo ">> Current node count: ${NODE_BEFORE}"
  echo ""

  echo ">> Scaling down compute-intensive workload to 0..."
  kubectl scale deployment compute-intensive --replicas=0 -n "${NAMESPACE}"

  echo ""
  echo ">> Auto Mode evaluates underutilization after 30s, then consolidates."
  echo ">> Watch eks-node-viewer (top pane) — a node should drain and disappear."
  echo ">> Watch k9s (bottom-left) — pods will be rescheduled."
  echo ""
  echo ">> Waiting ~90 seconds for consolidation..."

  for i in $(seq 1 9); do
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
  echo ">> Final node count: ${NODE_AFTER} (was ${NODE_BEFORE})"
  echo ">> Pods consolidated:"
  kubectl get pods -n "${NAMESPACE}" -o wide

  echo ""
  echo "✓ Part 3 complete. Check CloudWatch dashboard for utilization changes."
}

# ─── Part 4: Sub-Minute Scaling ──────────────────────────────────────────────
part4() {
  print_header "PART 4: Sub-Minute Scaling (2-3 min)"

  echo ">> Scaling sample-app to 10 replicas..."
  START=$(date +%s)
  kubectl scale deployment sample-app --replicas=10 -n "${NAMESPACE}"

  echo ""
  echo ">> Watch eks-node-viewer (top pane) for new node appearing..."
  echo ">> Watch k9s (bottom-left) for pods going Pending → Running..."
  echo ""
  echo ">> Waiting for all pods to be ready (timeout 120s)..."
  kubectl wait --for=condition=Ready pod -l app=sample-app \
    -n "${NAMESPACE}" --timeout=120s 2>/dev/null || \
    echo "   (some pods may still be starting)"

  END=$(date +%s)
  ELAPSED=$((END - START))

  echo ""
  echo ">> All pods ready in ${ELAPSED} seconds."
  echo ">> Final state:"
  kubectl get nodes -o wide
  echo ""
  kubectl get pods -n "${NAMESPACE}" -o wide

  echo ""
  echo "✓ Part 4 complete. Sub-minute scaling demonstrated."
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────
cleanup() {
  print_header "CLEANUP"

  echo ">> Resetting deployments..."
  kubectl scale deployment sample-app --replicas=3 -n "${NAMESPACE}" 2>/dev/null || true
  kubectl scale deployment compute-intensive --replicas=0 -n "${NAMESPACE}" 2>/dev/null || true

  echo ">> Current state:"
  kubectl get pods -n "${NAMESPACE}"
  echo ""
  echo "✓ Reset to initial demo state (3 sample-app pods)."
}

# ─── Menu ────────────────────────────────────────────────────────────────────
show_menu() {
  echo ""
  echo "┌──────────────────────────────────────────┐"
  echo "│  EKS Auto Mode Demo — Choose a section   │"
  echo "├──────────────────────────────────────────┤"
  echo "│  1) Part 1: Initial State & Spot         │"
  echo "│  2) Part 2: Intelligent Instance Select  │"
  echo "│  3) Part 3: Continuous Consolidation     │"
  echo "│  4) Part 4: Sub-Minute Scaling           │"
  echo "│  c) Cleanup / Reset                      │"
  echo "│  q) Quit                                 │"
  echo "└──────────────────────────────────────────┘"
  echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────
if [ -z "$1" ]; then
  while true; do
    show_menu
    read -p "  Choice: " choice
    case $choice in
      1) part1 ;;
      2) part2 ;;
      3) part3 ;;
      4) part4 ;;
      c|C) cleanup ;;
      q|Q) exit 0 ;;
      *) echo "  Invalid choice." ;;
    esac
  done
else
  case $1 in
    part1) part1 ;;
    part2) part2 ;;
    part3) part3 ;;
    part4) part4 ;;
    cleanup) cleanup ;;
    *) echo "Usage: $0 [part1|part2|part3|part4|cleanup]"; exit 1 ;;
  esac
fi
