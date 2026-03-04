# Use Case 2: Intelligent Instance Selection

## Business Value
Eliminate over-provisioning and reduce costs by 30-50% through automatic selection of optimal instance types based on actual workload requirements.

## Demo Steps (3-4 minutes)

### Step 1: Deploy Compute-Intensive Workload
```bash
kubectl apply -f manifests/03-compute-intensive-workload.yaml
```

Workload details:
- 2 replicas
- 2 CPU cores per pod (4 cores total)
- 512Mi memory per pod

Expected: Command completes in <2 seconds

### Step 2: Watch Node Provisioning
```bash
kubectl get nodes -w
```

Expected timeline:
- T+0s: Command executed
- T+45-60s: New node appears and becomes Ready

Press Ctrl+C to stop watching once node is Ready

### Step 3: Verify Pods are Running
```bash
kubectl get pods -n demo-app -o wide
```

Expected: Shows all pods including 2 compute-intensive pods in Running state, distributed across nodes

### Step 4: View Node Details
```bash
kubectl get nodes -o wide
```

Expected: Shows 2 nodes with instance types automatically selected by Auto Mode

## Talking Points

- Auto Mode analyzes CPU/memory requirements automatically
- Selects appropriate instance type from c, m, r families (100+ instance types)
- Provisions new capacity in under 60 seconds
- No manual instance type configuration needed
- 30-50% cost savings vs. manual instance selection
- Zero configuration required

## Key Metrics
- Node Provisioning Time: 45-60 seconds (sub-minute)
- Cost Optimization: 30-50% savings vs. manual instance selection
- Instance Families: Automatically selects from 100+ instance types
- Configuration Required: Zero
