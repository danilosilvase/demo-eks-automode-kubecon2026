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

# Show the nodes a given app's pods landed on: instance type, CPU architecture,
# Spot or On-Demand. Prints what actually happened, never an assumed family.
show_placement() {
  local app="$1"
  local nodes
  nodes=$(kubectl get pods -n "${NAMESPACE}" -l app="${app}" \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ')
  if [ -n "${nodes// /}" ]; then
    echo "  \$ kubectl get nodes (where ${app} runs)"
    # shellcheck disable=SC2086
    kubectl get nodes ${nodes} -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type
  fi
}

# ─── 1. Zero-config provisioning ─────────────────────────────────────────────
step_simple_workload() {
  print_header "Zero config: no Karpenter to install or run"

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

# ─── 2. Spot + Graviton with one NodePool ────────────────────────────────────
step_spot_nodepool() {
  print_header "Spot + Graviton: one NodePool, Karpenter already there"

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
  show_placement compute-intensive
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
  show_placement memory-intensive
}

# ─── 5. Same app on Graviton ─────────────────────────────────────────────────
step_graviton() {
  print_header "Same app, Graviton (arm64): no rebuild"

  GRAV_START=$(date +%s)
  echo "  \$ kubectl apply -f 07-graviton-workload.yaml"
  kubectl apply -f "${MANIFESTS_DIR}/07-graviton-workload.yaml"

  echo ""
  for i in $(seq 1 24); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - GRAV_START ))
    READY=$(kubectl get pods -n "${NAMESPACE}" -l app=sample-app-graviton --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Pods: %s/3\n" "${ELAPSED}" "${READY}"
    if [ "${READY}" -ge 3 ]; then
      echo "   ✓ Ready in ${ELAPSED}s"
      break
    fi
  done

  echo ""
  show_placement sample-app-graviton
}

# ─── 7. Consolidation ────────────────────────────────────────────────────────
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
  echo "  \$ kubectl scale deployment sample-app-graviton --replicas=0"
  kubectl scale deployment sample-app-graviton --replicas=0 -n "${NAMESPACE}" 2>/dev/null || true
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
  print_header "Rapid scaling"

  NODES_BEFORE=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  wait_prompt

  SCALE_START=$(date +%s)
  echo "  \$ kubectl scale deployment sample-app --replicas=50"
  kubectl scale deployment sample-app --replicas=50 -n "${NAMESPACE}"

  echo ""
  for i in $(seq 1 36); do
    sleep 5
    NOW=$(date +%s)
    ELAPSED=$(( NOW - SCALE_START ))
    CURRENT_NODES=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    READY_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=sample-app --no-headers 2>/dev/null | grep Running | wc -l | tr -d " ")
    printf "   [%3ds] Nodes: %s  Pods: %s/50\n" "${ELAPSED}" "${CURRENT_NODES}" "${READY_PODS}"
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
  echo "   ${NODES_BEFORE} → ${NODES_AFTER} nodes | 50 pods in ${TOTAL}s"
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
  echo "  1:provision  2:spot+graviton  3:cpu  4:memory  5:graviton  6:scale  7:consolidate  c:clean  q:quit"
  echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────
if [ -z "$1" ]; then
  clear
  show_menu
  while true; do
    read -p "  >> " choice
    case $choice in
      1) step_simple_workload; echo ""; echo "  next: 2:spot+graviton  c:clean" ;;
      2) step_spot_nodepool; echo ""; echo "  next: 3:cpu  c:clean" ;;
      3) step_cpu_workload; echo ""; echo "  next: 4:memory  c:clean" ;;
      4) step_memory_workload; echo ""; echo "  next: 5:graviton  c:clean" ;;
      5) step_graviton; echo ""; echo "  next: 6:scale  c:clean" ;;
      6) step_scaling; echo ""; echo "  next: 7:consolidate  c:clean" ;;
      7) step_consolidation; echo ""; echo "  c:clean  q:quit" ;;
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
    5|graviton) step_graviton ;;
    6|scaling) step_scaling ;;
    7|consolidation) step_consolidation ;;
    cleanup) step_cleanup ;;
    *) echo "Usage: $0 [1-7|cleanup]"; exit 1 ;;
  esac
fi
