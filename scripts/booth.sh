#!/bin/bash
# =============================================================================
# EKS Auto Mode demo: two-pane booth layout
#   top:    eks-node-viewer (live nodes, Spot/On-Demand, arch, $/hour)
#   bottom: scripts/demo.sh
# Runs inside tmux with 24-bit colour so the node-viewer bars match a desktop terminal.
#
#   ./scripts/booth.sh                 MODE=loop: runs all steps, then the recap (booth video)
#   MODE=live ./scripts/booth.sh       presenter menu (same as ./scripts/live.sh)
#   CLEAN=1   ./scripts/booth.sh       no captions, banners, timers or recap: plain kubectl
#   BONUS=1   ./scripts/booth.sh       loop mode only: add the Graviton step before the recap
#   PAUSE=8                            seconds between steps in loop mode
#   COLS / ROWS / TOP_ROWS             tmux size (defaults: current terminal, node-viewer 16 rows)
#
# Uses your current kubeconfig (KUBECONFIG or ~/.kube/config).
# Detach: Ctrl+B then D. Re-attach: tmux -L ekrec attach -t eks-rec
# =============================================================================
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${LOG:-${TMPDIR:-/tmp}/eks-demo-$(date +%Y%m%d-%H%M%S).log}"
S=eks-rec
T="tmux -L ekrec"
for cmd in tmux eks-node-viewer kubectl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: '$cmd' is not installed. Run ./scripts/setup-tools.sh first."; exit 1; }
done
# Size to the current terminal so it also fits narrower windows such as the EKS Workshop browser IDE.
COLS="${COLS:-$(tput cols 2>/dev/null || echo 150)}"
ROWS="${ROWS:-$(tput lines 2>/dev/null || echo 42)}"
export COLORTERM=truecolor
$T kill-server 2>/dev/null || true
$T -f "$REPO/scripts/tmux-truecolor.conf" new-session -d -s $S -x "$COLS" -y "$ROWS" -e COLORTERM=truecolor \
  "while true; do eks-node-viewer --node-sort=creation --resources cpu,memory --extra-labels kubernetes.io/arch 2>/dev/null; sleep 3; done"
$T set -g window-size latest
$T set -g aggressive-resize on
if [ "${CLEAN:-0}" != "1" ]; then
  $T set -g status-style "bg=colour214,fg=black,bold"
  $T set -g status-left-length 140
  $T set -g status-right ""
  $T set -g window-status-format ""
  $T set -g window-status-current-format ""
fi
$T split-window -v -t $S:0 -e COLORTERM=truecolor \
  "cd '$REPO' && MODE=${MODE:-loop} CLEAN=${CLEAN:-0} BONUS=${BONUS:-0} PAUSE=${PAUSE:-8} bash scripts/demo.sh 2>&1 | tee '$LOG'; sleep 3; tmux -L ekrec kill-session -t $S"
$T resize-pane -t $S:0.0 -y "${TOP_ROWS:-16}"
$T select-pane -t $S:0.1
$T attach -t $S
