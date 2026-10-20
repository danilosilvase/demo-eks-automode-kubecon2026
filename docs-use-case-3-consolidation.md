# Use Case: Consolidation

## Business Value
Reduce idle capacity costs by 40-60% through automatic workload consolidation during low-traffic periods.

## Demo Steps (3-4 minutes)

### Step 1: Show Current State
```bash
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```
Expected: 2-3 nodes, sized to the CPU and memory workloads, mostly Spot

### Step 2: Scale Down Workloads
```bash
kubectl scale deployment compute-intensive --replicas=0 -n demo-app
kubectl scale deployment memory-intensive --replicas=0 -n demo-app
```

### Step 3: Watch Consolidation with Timer
The demo script shows a live timer:
```
⏱  Timer started. Waiting for node removal...
   [ 5s] Nodes: 3
   [10s] Nodes: 3
   [35s] Nodes: 2
   ✓ Node removed in 35s
   [50s] Nodes: 1
```

Expected: Karpenter evaluates underutilization after 30s, then drains and removes nodes.

### Step 4: Verify Final State
```bash
kubectl get nodes
kubectl get pods -n demo-app -o wide
```
Expected: 1 node, 3 sample-app pods consolidated

## Talking Points

- "Watch the timer — consolidation starts after 30 seconds of underutilization"
- "Nodes drain gracefully, pods are rescheduled before the node is removed"
- "This happens automatically 24/7 — nights, weekends, any low-traffic period"
- "40-60% cost reduction during off-peak hours, zero manual intervention"

## Key Metrics
- Consolidation Time: 30s evaluation + ~30-60s drain = ~60-90s total
- Cost Savings: 40-60% during low-traffic periods
- Downtime: Zero — graceful pod migration
