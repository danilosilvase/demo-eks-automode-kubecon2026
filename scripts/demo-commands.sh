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
  echo "── $1 ──"
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

  echo "  \$ kubectl apply -f 01-namespace.yaml"
  kubectl apply -f "${MANIFESTS_DIR}/01-namespace.yaml"

  PROVISION_START=$(date +%s)
  echo "  \$ kubectl apply -f 02-sample-app.yaml"
  kubectl apply -f "${MANIFESTS_DIR}/02-sample-app.yaml"

  echo ""
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - PROVISION_START ))
    NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    READY=$(kubectl get pods -n "${NAMESPACE}" -l app=sample-app --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Nodes: %s  Pods: %s/3\n" "${ELAPSED}" "${NODES}" "${READY}"
    if [ "${READY}" -ge 3 ]; then
      echo "   ✓ Ready in ${ELAPSED}s"
      break
    fi
  done

  echo ""
  echo "  \$ kubectl get nodes"
  kubectl get nodes -L karpenter.sh/capacity-type,karpenter.sh/nodepool,node.kubernetes.io/instance-type
  echo ""
  echo "  \$ kubectl get pods -n ${NAMESPACE} -o wide"
  kubectl get pods -n "${NAMESPACE}" -o wide
}

# ─── 2. Enable Spot with a custom NodePool ───────────────────────────────────
step_spot_nodepool() {
  print_header "Enable Spot with a custom NodePool"

  echo "  \$ kubectl get nodepools"
  kubectl get nodepools
  wait_prompt

  echo "  \$ kubectl apply -f 00-cost-optimized-nodepool.yaml"
  kubectl apply -f "${MANIFESTS_DIR}/00-cost-optimized-nodepool.yaml"
  echo ""
  echo "  \$ kubectl get nodepools"
  kubectl get nodepools
  echo ""
  echo "  \$ kubectl describe nodepool cost-optimized"
  kubectl describe nodepool cost-optimized | grep -A20 "Spec:" | head -25
  wait_prompt

  for i in $(seq 1 18); do
    sleep 5
    SPOT=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "${SPOT}" -gt 0 ]; then
      echo "   ✓ Spot node detected ($(( i * 5 ))s)"
      break
    fi
  done

  echo ""
  echo "   On-Demand: $(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "   Spot:      $(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')"
}

# ─── 3. CPU-intensive workload ───────────────────────────────────────────────
step_cpu_workload() {
  print_header "CPU-intensive workload"

  CPU_START=$(date +%s)
  echo "  \$ kubectl apply -f 03-compute-intensive-workload.yaml"
  kubectl apply -f "${MANIFESTS_DIR}/03-compute-intensive-workload.yaml"

  echo ""
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - CPU_START ))
    READY=$(kubectl get pods -n "${NAMESPACE}" -l app=compute-intensive --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Pods: %s/2\n" "${ELAPSED}" "${READY}"
    if [ "${READY}" -ge 2 ]; then
      echo "   ✓ Ready in ${ELAPSED}s"
      break
    fi
  done

  echo ""
  echo "  \$ kubectl get nodes"
  kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type,\
POOL:.metadata.labels.karpenter\\.sh/nodepool
}

# ─── 4. Memory-intensive workload ────────────────────────────────────────────
step_memory_workload() {
  print_header "Memory-intensive workload"

  MEM_START=$(date +%s)
  echo "  \$ kubectl apply -f 04-memory-intensive-workload.yaml"
  kubectl apply -f "${MANIFESTS_DIR}/04-memory-intensive-workload.yaml"

  echo ""
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - MEM_START ))
    READY=$(kubectl get pods -n "${NAMESPACE}" -l app=memory-intensive --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Pods: %s/2\n" "${ELAPSED}" "${READY}"
    if [ "${READY}" -ge 2 ]; then
      echo "   ✓ Ready in ${ELAPSED}s"
      break
    fi
  done

  echo ""
  echo "  \$ kubectl get nodes"
  kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type,\
POOL:.metadata.labels.karpenter\\.sh/nodepool
}

# ─── 5. Consolidation ────────────────────────────────────────────────────────
step_consolidation() {
  print_header "Consolidation"

  NODE_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  echo "   Nodes: ${NODE_BEFORE}"
  echo "  \$ kubectl get nodes"
  kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
  wait_prompt

  echo "  \$ kubectl scale deployment compute-intensive --replicas=0"
  kubectl scale deployment compute-intensive --replicas=0 -n "${NAMESPACE}"
  echo "  \$ kubectl scale deployment memory-intensive --replicas=0"
  kubectl scale deployment memory-intensive --replicas=0 -n "${NAMESPACE}"
  echo "  \$ kubectl scale deployment sample-app --replicas=3"
  kubectl scale deployment sample-app --replicas=3 -n "${NAMESPACE}"

  CONSOLIDATION_START=$(date +%s)
  echo ""
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - CONSOLIDATION_START ))
    CURRENT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    printf "   [%3ds] Nodes: %s\n" "${ELAPSED}" "${CURRENT}"
    if [ "${CURRENT}" -lt "${NODE_BEFORE}" ]; then
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
  echo "   ${NODE_BEFORE} → ${NODE_AFTER} nodes (${TOTAL}s)"
  echo "  \$ kubectl get pods -n ${NAMESPACE} -o wide"
  kubectl get pods -n "${NAMESPACE}" -o wide
}

# ─── 6. Sub-minute scaling ───────────────────────────────────────────────────
step_scaling() {
  print_header "Sub-minute scaling"

  NODES_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  PODS_BEFORE=$(kubectl get pods -n "${NAMESPACE}" --no-headers | wc -l | tr -d ' ')
  echo "   ${NODES_BEFORE} node(s), ${PODS_BEFORE} pod(s)"
  wait_prompt

  SCALE_START=$(date +%s)
  echo "  \$ kubectl scale deployment sample-app --replicas=100"
  kubectl scale deployment sample-app --replicas=100 -n "${NAMESPACE}"

  echo ""
  for i in $(seq 1 36); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - SCALE_START ))
    CURRENT_NODES=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    READY_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=sample-app --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Nodes: %s  Pods: %s/100\n" "${ELAPSED}" "${CURRENT_NODES}" "${READY_PODS}"
    if [ "${CURRENT_NODES}" -gt "${NODES_BEFORE}" ]; then
      echo "   ✓ New node in ${ELAPSED}s"
      break
    fi
  done

  echo ""
  kubectl wait --for=condition=Ready pod -l app=sample-app \
    -n "${NAMESPACE}" --timeout=300s &>/dev/null || true

  NOW=$(date +%s)
  TOTAL=$(( NOW - SCALE_START ))
  NODES_AFTER=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')

  echo ""
  echo "   ${NODES_BEFORE} → ${NODES_AFTER} nodes | 100 pods in ${TOTAL}s"
  echo "  \$ kubectl get nodes"
  kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────
step_cleanup() {
  print_header "Cleanup / Reset"

  echo "  \$ kubectl delete namespace ${NAMESPACE}"
  kubectl delete namespace "${NAMESPACE}" --wait=false 2>/dev/null || true
  echo "  \$ kubectl delete nodepool cost-optimized"
  kubectl delete nodepool cost-optimized 2>/dev/null || true

  for i in $(seq 1 12); do
    sleep 10
    NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "${NODES}" -eq 0 ]; then break; fi
  done

  echo "   ✓ Reset. Run step 1 to start fresh."
}

# ─── Menu ────────────────────────────────────────────────────────────────────
show_menu() {
  echo ""
  echo "  1:provision  2:cpu  3:memory  4:spot  5:scale  6:consolidate  c:clean  q:quit"
  echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────
if [ -z "$1" ]; then
  clear
  show_menu
  while true; do
    read -p "  >> " choice
    case $choice in
      1) step_simple_workload; echo ""; echo "  next: 2:cpu  c:clean" ;;
      2) step_cpu_workload; echo ""; echo "  next: 3:memory  c:clean" ;;
      3) step_memory_workload; echo ""; echo "  next: 4:spot  c:clean" ;;
      4) step_spot_nodepool; echo ""; echo "  next: 5:scale  c:clean" ;;
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
    2|cpu) step_cpu_workload ;;
    3|memory) step_memory_workload ;;
    4|spot) step_spot_nodepool ;;
    5|scaling) step_scaling ;;
    6|consolidation) step_consolidation ;;
    cleanup) step_cleanup ;;
    *) echo "Usage: $0 [1-6|cleanup]"; exit 1 ;;
  esac
fi
