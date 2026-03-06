# Use Case: Sub-Minute Scaling

## Business Value
Handle traffic spikes without over-provisioning. New nodes provisioned in under 60 seconds.

## Demo Steps (2-3 minutes)

### Step 1: Show Current State
```bash
kubectl get nodes
kubectl get pods -n demo-app
```
Expected: 1 node, 3 sample-app pods

### Step 2: Scale Up
```bash
kubectl scale deployment sample-app --replicas=30 -n demo-app
```

### Step 3: Watch Scaling with Timer
The demo script shows a live timer:
```
⏱  Timer started. Waiting for new node...
   [ 5s] Nodes: 1  Pods running: 3/30
   [10s] Nodes: 1  Pods running: 3/30
   [45s] Nodes: 2  Pods running: 15/30
   ✓ New node provisioned in 45s

Waiting for all 30 pods...
>> Nodes: 1 → 2  |  All 30 pods ready in 62s
```

### Step 4: Verify Final State
```bash
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```
Expected: 2+ nodes, all Spot, 30 pods running

## Talking Points

- "We went from 3 to 30 replicas — watch the timer"
- "New node provisioned in under 60 seconds"
- "All 30 pods serving traffic in about a minute"
- "No pre-provisioned capacity needed — pay only when you need it"

## Key Metrics
- Node Provisioning: <60 seconds
- All Pods Ready: ~60-75 seconds total
- Pre-provisioning Required: None
