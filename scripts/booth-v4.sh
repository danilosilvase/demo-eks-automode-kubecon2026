#!/bin/bash
# =============================================================================
# EKS Auto Mode demo v4: two-pane booth layout (eks-node-viewer on top, demo below)
# Runs scripts/demo-v4.sh inside tmux, in full 24-bit colour so the node-viewer
# bars look the same as in a desktop terminal.
#
#   MODE=loop  (default) booth / recording: runs all steps, then the recap
#   MODE=live  presenter menu (Enter = next step, 1-6, g, r, c, q)
#   CLEAN=1    no captions, banners, timers or recap: plain kubectl, default tmux bar
#   BONUS=1    loop mode only: add the Graviton step before the recap
#
# Uses your current kubeconfig (KUBECONFIG or ~/.kube/config).
# =============================================================================
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${LOG:-${TMPDIR:-/tmp}/eks-demo-v4-$(date +%Y%m%d-%H%M%S).log}"
S=eks-rec
T="tmux -L ekrec"
for cmd in tmux eks-node-viewer kubectl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: '$cmd' is not installed. Run ./scripts/setup-tools.sh first."; exit 1; }
done
export COLORTERM=truecolor
$T kill-server 2>/dev/null || true
$T -f "$REPO/scripts/tmux-truecolor.conf" new-session -d -s $S -x "${COLS:-150}" -y "${ROWS:-42}" -e COLORTERM=truecolor \
  "while true; do eks-node-viewer --node-sort=creation --resources cpu,memory --extra-labels kubernetes.io/arch 2>/dev/null; sleep 3; done"
if [ "${CLEAN:-0}" != "1" ]; then
  $T set -g status-style "bg=colour214,fg=black,bold"
  $T set -g status-left-length 140
  $T set -g status-right ""
  $T set -g window-status-format ""
  $T set -g window-status-current-format ""
fi
$T split-window -v -t $S:0 -e COLORTERM=truecolor \
  "cd '$REPO' && MODE=${MODE:-loop} CLEAN=${CLEAN:-0} BONUS=${BONUS:-0} MANIFESTS_DIR=manifests PAUSE=${PAUSE:-8} bash scripts/demo-v4.sh 2>&1 | tee '$LOG'; sleep 3; tmux -L ekrec kill-session -t $S"
$T resize-pane -t $S:0.0 -y 16
$T select-pane -t $S:0.1
$T attach -t $S
