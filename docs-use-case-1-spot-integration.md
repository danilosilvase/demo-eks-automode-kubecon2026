# Use Case 1: Spot Instance Integration

## Business Value
Reduce compute costs by up to 90% through automatic Spot instance utilization without application changes or manual configuration.

## Demo Steps (2-3 minutes)

### Step 1: View Current Cluster State
```bash
kubectl get nodes
```
Expected: Shows 1 node running with sample application

### Step 2: View NodePools Configuration
```bash
kubectl get nodepools
```
Expected: Shows `general-purpose` and `system` nodepools

### Step 3: Inspect NodePool Details
```bash
kubectl describe nodepool general-purpose
```

Key information to highlight:
- Capacity Type: on-demand (default, can be configured for Spot)
- Instance Families: c, m, r (compute, general, memory optimized)
- Consolidation Policy: WhenEmptyOrUnderutilized
- Consolidate After: 30s

### Step 4: View Running Pods
```bash
kubectl get pods -n demo-app
```
Expected: Shows 3 sample-app pods in Running state

## Talking Points

- Auto Mode automatically provisions nodes based on workload requirements
- Default uses on-demand instances, but Spot can be configured in NodePool
- No manual node management required
- Consolidation happens automatically after 30 seconds of underutilization
- Spot integration provides up to 90% cost savings with graceful interruption handling

## Key Metrics
- Cost Savings: Up to 90% reduction on compute costs
- Configuration Time: Zero - works out of the box
- Interruption Handling: Automatic with zero downtime
