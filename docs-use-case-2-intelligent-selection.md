# Use Case 2: Intelligent Instance Selection

## Business Value
Eliminate over-provisioning and reduce costs by 30-50% through automatic selection of optimal instance types based on actual workload requirements.

## Demo Steps (3-4 minutes)

### Step 1: Deploy Compute-Intensive Workload
```bash
kubectl apply -f manifests/03-compute-intensive-workload.yaml
```

Workload details:
- 2 replicas, 2 CPU cores per pod (4 cores total), 512Mi memory
- High CPU-to-memory ratio → triggers c-family (compute-optimized) selection

### Step 2: Deploy Memory-Intensive Workload
```bash
kubectl apply -f manifests/04-memory-intensive-workload.yaml
```

Workload details:
- 2 replicas, 250m CPU per pod, 8Gi memory per pod (16Gi total)
- High memory-to-CPU ratio → triggers r-family (memory-optimized) selection

### Step 3: Watch Node Provisioning
```bash
kubectl get nodes -w
```

Expected timeline:
- T+0s: Commands executed
- T+45-60s: New nodes appear and become Ready
- Compute workload → c-family instance (e.g., c6a.2xlarge)
- Memory workload → r-family instance (e.g., r5a.large)

### Step 4: Verify Instance Family Selection
```bash
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type
```

Expected: Different instance families selected for each workload type

### Step 5: View Pod Distribution
```bash
kubectl get pods -n demo-app -o wide
```

Expected: Compute pods on c-family nodes, memory pods on r-family nodes

## Talking Points

- "We deployed two workloads with very different resource profiles"
- "Karpenter analyzed the CPU and memory requirements independently"
- "Compute workload got a c-family instance — optimized for CPU"
- "Memory workload got an r-family instance — optimized for memory"
- "No manual instance type configuration — Auto Mode figured it out"
- "This avoids over-provisioning: you don't pay for memory you don't need on compute nodes, or CPU you don't need on memory nodes"

## Key Metrics
- Node Provisioning Time: 45-60 seconds (sub-minute)
- Cost Optimization: 30-50% savings vs. manual one-size-fits-all selection
- Instance Families: Automatically selects from c, m, r (100+ instance types)
- Configuration Required: Zero
