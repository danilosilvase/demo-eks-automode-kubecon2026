#!/bin/bash
# Reset the cluster to zero worker nodes (about 1 to 3 minutes). Run before each live demo or recording.
K="kubectl --request-timeout=20s"
$K delete namespace demo-app --wait=false --ignore-not-found
$K delete nodepool cost-optimized --ignore-not-found
for i in $(seq 1 30); do
  n=$($K get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  ns=$($K get ns demo-app --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "  nodes: $n   demo namespace present: $ns"
  [ "$n" -eq 0 ] && [ "$ns" -eq 0 ] && { echo "  ✓ Ready for a clean run"; exit 0; }
  sleep 10
done
echo "  Still not empty after 5 min; check 'kubectl get nodes,nodeclaims'"; exit 1
