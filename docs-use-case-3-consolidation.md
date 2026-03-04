# Use Case 3: Continuous Consolidation

## Business Value
Reduce idle capacity costs by 40-60% through automatic workload consolidation during low-traffic periods, with no manual intervention required.

## Demo Steps (4-5 minutes)

### Step 1: Show Current State
```bash
kubectl get nodes
```
Expected: 2 nodes running

```bash
kubectl get pods -n demo-app
```
Expected: 5 pods running (3 sample-app + 2 compute-intensive)

### Step 2: Scale Down Compute Workload
```bash
kubectl scale deployment compute-intensive --replicas=0 -n demo-app
```

This simulates low-traffic period or workload completion

Expected: Command completes in <1 second

### Step 3: Verify Pods Terminated
```bash
kubectl get pods -n demo-app
```

Expected: Only 3 sample-app pods remain (compute-intensive pods terminated in ~5 seconds)

### Step 4: Watch Consolidation
```bash
kubectl get nodes -w
```

Expected timeline:
- T+0s: Still showing 2 nodes
- T+30s: Consolidation evaluation begins (underutilization detected)
- T+60-90s: Second node status changes to NotReady, then disappears
- Final state: 1 node with all 3 sample-app pods

Press Ctrl+C to stop watching once consolidation completes

### Step 5: Verify Final State
```bash
kubectl get nodes
```
Expected: Back to 1 node

```bash
kubectl get pods -n demo-app -o wide
```
Expected: All 3 sample-app pods running on single node

## Talking Points

- Consolidation happens automatically after 30s of underutilization
- Workloads gracefully moved to remaining nodes (zero downtime)
- No manual intervention required
- Reduces costs during low-traffic periods (nights, weekends)
- 40-60% cost reduction during off-peak hours
- Happens continuously 24/7 without human intervention

## Key Metrics
- Consolidation Time: 60-90 seconds after 30-second evaluation period
- Cost Savings: 40-60% reduction during low-traffic periods
- Downtime: Zero - graceful workload migration
- Daily Savings: Applies automatically during off-peak hours
