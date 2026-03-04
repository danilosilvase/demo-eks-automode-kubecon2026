# Use Case 4: Sub-Minute Scaling

## Business Value
Handle traffic spikes efficiently without over-provisioning, reducing costs while maintaining performance. Scale from 3 to 10 replicas in under 75 seconds total.

## Demo Steps (2-3 minutes)

### Step 1: Show Current State
```bash
kubectl get nodes
```
Expected: 1 node running

```bash
kubectl get pods -n demo-app
```
Expected: 3 sample-app pods running

### Step 2: Scale Up Application
```bash
kubectl scale deployment sample-app --replicas=10 -n demo-app
```

This simulates a traffic burst or demand spike

Expected: Command completes in <1 second

### Step 3: Watch Scaling Progress
```bash
kubectl get pods -n demo-app -w
```

Expected timeline:
- T+0s: 7 new pods created in Pending state
- T+45-60s: New node provisioned and Ready
- T+75s: All 10 pods in Running state

Press Ctrl+C to stop watching once all pods are Running

### Step 4: Verify Final State
```bash
kubectl get nodes
```
Expected: 2 nodes running

```bash
kubectl get pods -n demo-app
```
Expected: 10 sample-app pods in Running state

## Talking Points

- Sub-minute node provisioning (45-60 seconds)
- Pods scheduled immediately when capacity available
- Automatic scaling without manual intervention
- Handles traffic spikes efficiently
- Pay only for capacity when needed (no pre-provisioning required)
- Total time from scale command to all pods serving traffic: ~75 seconds

## Key Metrics
- Scaling Speed: 45-60 seconds for new node provisioning
- Total Time to Serve: ~75 seconds from scale command to all pods running
- Cost Impact: Pay only for capacity when needed
- Pre-provisioning Required: None
