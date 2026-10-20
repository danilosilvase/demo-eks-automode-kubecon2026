#!/bin/bash
# =============================================================================
# EKS Auto Mode demo, live presenter mode (booth layout + menu).
#   ./scripts/live.sh            captions, step banner, results tally
#   CLEAN=1 ./scripts/live.sh    plain kubectl, as if typing on your laptop
# Menu: Enter = suggested next step | 1-6 steps | g Graviton bonus | r recap | c reset | q quit
# Run ./scripts/reset-demo.sh first for a clean start (or press c in the menu).
# =============================================================================
DIR="$(cd "$(dirname "$0")" && pwd)"
kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1 || {
  echo "Cannot reach the cluster API. Check your kubeconfig, and that ./scripts/tunnel.sh is running (private endpoint)."; exit 1; }
[ "$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] || \
  echo "Note: cluster is not empty. Press c in the menu (or run ./scripts/reset-demo.sh) for a clean start."
MODE=live exec "$DIR/booth.sh"
