#!/bin/bash
# =============================================================================
# EKS Auto Mode Demo — Visual Orchestrator
# =============================================================================
# Launches a tmux session with two panes:
#
#   ┌─────────────────────────────────────────┐
#   │                                         │
#   │         eks-node-viewer                 │
#   │    (real-time node utilization bars)    │
#   │                                         │
#   ├─────────────────────────────────────────┤
#   │                                         │
#   │         Command terminal                │
#   │                                         │
#   └─────────────────────────────────────────┘
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
for cmd in tmux eks-node-viewer kubectl; do
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
tmux new-session -d -s "${SESSION}" -x 220 -y 60 \
  "while true; do eks-node-viewer --kubeconfig ~/.kube/config --node-sort=creation --extra-labels karpenter.sh/capacity-type 2>/dev/null; echo 'eks-node-viewer restarting in 3s...'; sleep 3; done"

# Auto-resize panes when terminal window changes (zoom in/out)
tmux set-option -g window-size latest
tmux set-window-option -g aggressive-resize on

# Pane 1: Command terminal (bottom, full width)
tmux split-window -v -t "${SESSION}:0" \
  "echo '  Run: ./scripts/demo-commands.sh'; echo ''; exec bash"

# --- Layout ---
# Give the command terminal a fixed height; eks-node-viewer gets the rest
tmux resize-pane -t "${SESSION}:0.0" -y 22

# Select the command terminal pane
tmux select-pane -t "${SESSION}:0.1"

echo "Attaching to tmux session '${SESSION}'..."
echo "(Detach with Ctrl+B then D. Kill with: tmux kill-session -t ${SESSION})"
echo ""

# Attach
tmux attach-session -t "${SESSION}"
