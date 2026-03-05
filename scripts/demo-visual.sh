#!/bin/bash
# =============================================================================
# EKS Auto Mode Demo — Visual Orchestrator
# =============================================================================
# Launches a tmux session with three panes:
#
#   ┌─────────────────────────────────────────┐
#   │                                         │
#   │         eks-node-viewer                 │
#   │    (real-time node utilization bars)    │
#   │                                         │
#   ├────────────────────┬────────────────────┤
#   │                    │                    │
#   │   k9s (pods view)  │  Command terminal  │
#   │                    │                    │
#   └────────────────────┴────────────────────┘
#
# Usage:
#   ./demo-visual.sh                    # defaults
#   ./demo-visual.sh my-cluster us-west-2
#
# Prerequisites:
#   Run ./scripts/setup-tools.sh first to install required tools.
# =============================================================================

set -e

CLUSTER_NAME="${1:-eks-auto-demo}"
REGION="${2:-eu-central-1}"
SESSION="eks-demo"
NAMESPACE="demo-app"

# --- Pre-flight checks ---
for cmd in tmux eks-node-viewer k9s kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed. Run ./scripts/setup-tools.sh first."
    exit 1
  fi
done

# Kill existing session if present
tmux kill-session -t "${SESSION}" 2>/dev/null || true

echo "=== Launching EKS Auto Mode Demo Visual ==="
echo "Cluster:   ${CLUSTER_NAME}"
echo "Region:    ${REGION}"
echo "Namespace: ${NAMESPACE}"
echo "Session:   ${SESSION}"
echo ""

# --- Create tmux session ---
# Pane 0: eks-node-viewer (top, full width)
tmux new-session -d -s "${SESSION}" -x 200 -y 50 \
  "eks-node-viewer --kubeconfig ~/.kube/config --node-sort=creation --extra-labels karpenter.sh/capacity-type 2>&1 || { echo 'eks-node-viewer exited. Press Enter to close.'; read; }"

# Split bottom half horizontally
# Pane 1: k9s (bottom-left)
tmux split-window -v -t "${SESSION}:0" \
  "k9s --namespace ${NAMESPACE} --command pods 2>&1 || { echo 'k9s exited. Press Enter to close.'; read; }"

# Pane 2: Command terminal (bottom-right)
tmux split-window -h -t "${SESSION}:0.1" \
  "echo ''; \
   echo '╔══════════════════════════════════════════════════════╗'; \
   echo '║  EKS Auto Mode Demo — Command Terminal              ║'; \
   echo '║                                                      ║'; \
   echo '║  Cluster: ${CLUSTER_NAME}                            ║'; \
   echo '║  Region:  ${REGION}                                  ║'; \
   echo '║  NS:      ${NAMESPACE}                               ║'; \
   echo '║                                                      ║'; \
   echo '║  Quick commands:                                     ║'; \
   echo '║    kubectl get nodes -o wide                         ║'; \
   echo '║    kubectl get pods -n ${NAMESPACE} -o wide          ║'; \
   echo '║    kubectl get nodepools                             ║'; \
   echo '║                                                      ║'; \
   echo '║  CloudWatch dashboard:                               ║'; \
   echo '║    Open browser to the URL printed by                ║'; \
   echo '║    ./cloudwatch/deploy-dashboard.sh                  ║'; \
   echo '╚══════════════════════════════════════════════════════╝'; \
   echo ''; \
   exec bash"

# --- Layout: top pane gets 60% height ---
tmux select-layout -t "${SESSION}:0" main-horizontal
# Resize top pane to ~60%
tmux resize-pane -t "${SESSION}:0.0" -y 30

# Select the command terminal pane
tmux select-pane -t "${SESSION}:0.2"

echo "Attaching to tmux session '${SESSION}'..."
echo "(Detach with Ctrl+B then D. Kill with: tmux kill-session -t ${SESSION})"
echo ""

# Attach
tmux attach-session -t "${SESSION}"
