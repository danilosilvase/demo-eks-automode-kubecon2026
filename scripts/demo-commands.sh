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
  clear
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

# ─── 1. Zero-config provisioning ─────────────────────────────────────────────
step_simple_workload() {
  print_header "Zero-config provisioning"

  echo ">> Creating namespace and deploying sample app (3 replicas)..."
  kubectl apply -f "${MANIFESTS_DIR}/01-namespace.yaml"

  PROVISION_START=$(date +%s)
  kubectl apply -f "${MANIFESTS_DIR}/02-sample-app.yaml"

  echo ""
  echo ">> ⏱ Waiting for node and pods..."
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - PROVISION_START ))
    NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    READY=$(kubectl get pods -n "${NAMESPACE}" -l app=sample-app --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Nodes: %s  Pods running: %s/3\n" "${ELAPSED}" "${NODES}" "${READY}"
    if [ "${READY}" -ge 3 ]; then
      echo ""
      echo "   ✓ Node provisioned and all pods ready in ${ELAPSED}s"
      break
    fi
  done

  echo ""
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
  kubectl get nodepools
  echo ""
  kubectl describe nodepool cost-optimized | grep -A20 "Spec:" | head -25
  wait_prompt

  echo ">> ⏱ Waiting for Spot node..."
  for i in $(seq 1 18); do
    sleep 5
    SPOT=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "   [$(( i * 5 ))s] Spot nodes: ${SPOT}"
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

  CPU_START=$(date +%s)
  echo ">> Deploying compute-intensive workload (2 CPU cores per pod, 2 replicas)..."
  kubectl apply -f "${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"

  echo ""
  echo ">> ⏱ Waiting for c-family instance..."
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - CPU_START ))
    READY=$(kubectl get pods -n "${NAMESPACE}" -l app=compute-intensive --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Pods running: %s/2\n" "${ELAPSED}" "${READY}"
    if [ "${READY}" -ge 2 ]; then
      echo ""
      echo "   ✓ Compute pods ready in ${ELAPSED}s"
      break
    fi
  done

  echo ""
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

  MEM_START=$(date +%s)
  echo ">> Deploying memory-intensive workload (8Gi per pod, 2 replicas)..."
  kubectl apply -f "${MANIFESTS_DIR}/04-memory-intensive-workload.yaml"

  echo ""
  echo ">> ⏱ Waiting for r-family instance..."
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - MEM_START ))
    READY=$(kubectl get pods -n "${NAMESPACE}" -l app=memory-intensive --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Pods running: %s/2\n" "${ELAPSED}" "${READY}"
    if [ "${READY}" -ge 2 ]; then
      echo ""
      echo "   ✓ Memory pods ready in ${ELAPSED}s"
      break
    fi
  done

  echo ""
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

  echo ">> Scaling down all workloads..."
  kubectl scale deployment compute-intensive --replicas=0 -n "${NAMESPACE}"
  kubectl scale deployment memory-intensive --replicas=0 -n "${NAMESPACE}"
  kubectl scale deployment sample-app --replicas=3 -n "${NAMESPACE}"

  CONSOLIDATION_START=$(date +%s)
  echo ""
  echo ">> ⏱ Waiting for node removal..."
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - CONSOLIDATION_START ))
    CURRENT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    printf "   [%3ds] Nodes: %s\n" "${ELAPSED}" "${CURRENT}"
    if [ "${CURRENT}" -lt "${NODE_BEFORE}" ]; then
      echo ""
      echo "   ✓ Node removed in ${ELAPSED}s"
      break
    fi
  done

  for i in $(seq 1 12); do
    CURRENT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    if [ "${CURRENT}" -le 1 ]; then break; fi
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - CONSOLIDATION_START ))
    printf "   [%3ds] Nodes: %s\n" "${ELAPSED}" "${CURRENT}"
  done

  NOW=$(date +%s)
  TOTAL=$(( NOW - CONSOLIDATION_START ))
  NODE_AFTER=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')

  echo ""
  echo ">> Nodes: ${NODE_BEFORE} → ${NODE_AFTER}  (${TOTAL}s)"
  kubectl get pods -n "${NAMESPACE}" -o wide

  echo ""
  echo "✓ Consolidated in ${TOTAL}s."
}

# ─── 6. Sub-minute scaling ───────────────────────────────────────────────────
step_scaling() {
  print_header "Sub-minute scaling"

  NODES_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  PODS_BEFORE=$(kubectl get pods -n "${NAMESPACE}" --no-headers | wc -l | tr -d ' ')
  echo ">> Current state: ${NODES_BEFORE} node(s), ${PODS_BEFORE} pod(s)"
  wait_prompt

  SCALE_START=$(date +%s)
  echo ">> Scaling sample-app to 30 replicas..."
  kubectl scale deployment sample-app --replicas=30 -n "${NAMESPACE}"

  echo ""
  echo ">> ⏱ Waiting for new node..."
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - SCALE_START ))
    CURRENT_NODES=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    READY_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=sample-app --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Nodes: %s  Pods running: %s/30\n" "${ELAPSED}" "${CURRENT_NODES}" "${READY_PODS}"
    if [ "${CURRENT_NODES}" -gt "${NODES_BEFORE}" ]; then
      echo ""
      echo "   ✓ New node provisioned in ${ELAPSED}s"
      break
    fi
  done

  echo ""
  echo ">> Waiting for all 30 pods..."
  kubectl wait --for=condition=Ready pod -l app=sample-app \
    -n "${NAMESPACE}" --timeout=180s 2>/dev/null || true

  NOW=$(date +%s)
  TOTAL=$(( NOW - SCALE_START ))
  NODES_AFTER=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')

  echo ""
  echo ">> Nodes: ${NODES_BEFORE} → ${NODES_AFTER}  |  All 30 pods ready in ${TOTAL}s"
  kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type

  echo ""
  echo "✓ Sub-minute scaling — ${TOTAL}s."
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────
step_cleanup() {
  print_header "Cleanup / Reset"

  echo ">> Deleting demo-app namespace..."
  kubectl delete namespace "${NAMESPACE}" --wait=false 2>/dev/null || true

  echo ">> Removing cost-optimized NodePool..."
  kubectl delete nodepool cost-optimized 2>/dev/null || true

  echo ">> Waiting for nodes to drain..."
  for i in $(seq 1 12); do
    sleep 10
    NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "${NODES}" -eq 0 ]; then break; fi
  done

  echo ""
  echo "✓ Reset. Run step 1 to start fresh."
}

# ─── Menu ────────────────────────────────────────────────────────────────────
show_menu() {
  echo ""
  echo "  1:provision  2:spot  3:cpu  4:memory  5:scale  6:consolidate  c:clean  q:quit"
  echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────
if [ -z "$1" ]; then
  show_menu
  while true; do
    read -p "  >> " choice
    case $choice in
      1) step_simple_workload; echo ""; echo "  next: 2:spot  c:clean" ;;
      2) step_spot_nodepool; echo ""; echo "  next: 3:cpu  c:clean" ;;
      3) step_cpu_workload; echo ""; echo "  next: 4:memory  c:clean" ;;
      4) step_memory_workload; echo ""; echo "  next: 5:scale  c:clean" ;;
      5) step_scaling; echo ""; echo "  next: 6:consolidate  c:clean" ;;
      6) step_consolidation; echo ""; echo "  c:clean  q:quit" ;;
      c|C) step_cleanup; echo ""; echo "  next: 1:provision" ;;
      q|Q) exit 0 ;;
      ""|n|N) ;;
      h|H|help) show_menu ;;
      *) echo "  ?  h for help" ;;
    esac
  done
else
  case $1 in
    1|provision) step_simple_workload ;;
    2|spot) step_spot_nodepool ;;
    3|cpu) step_cpu_workload ;;
    4|memory) step_memory_workload ;;
    5|scaling) step_scaling ;;
    6|consolidation) step_consolidation ;;
    cleanup) step_cleanup ;;
    *) echo "Usage: $0 [1-6|cleanup]"; exit 1 ;;
  esac
fi
