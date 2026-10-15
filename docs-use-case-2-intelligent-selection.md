# Use Case 2: Intelligent Instance Selection

## Business Value
Eliminate over-provisioning and reduce costs by 30-50% through automatic selection of optimal instance types based on actual workload requirements.

## Demo Steps (3-4 minutes)

### Step 1: Deploy Compute-Intensive Workload
```bash
kubectl apply -f manifests/03-compute-intensive-workload.yaml
```

Workload details:
- 2 replicas, 2 CPU cores per pod (4 cores total), 1Gi memory
- High CPU-to-memory ratio, so Karpenter usually picks a c-family (compute-optimized) instance

### Step 2: Deploy Memory-Intensive Workload
```bash
kubectl apply -f manifests/04-memory-intensive-workload.yaml
```

Workload details:
- 2 replicas, 250m CPU per pod, 8Gi memory per pod (16Gi total)
- High memory-to-CPU ratio, so Karpenter usually picks an r-family (memory-optimized) instance

### Step 3: Watch Node Provisioning
```bash
kubectl get nodes -w
```

Expected timeline:
- T+0s: Commands executed
- T+45-60s: New nodes appear and become Ready
- Karpenter picks the cheapest instance that fits each workload, x86 or AWS Graviton, Spot when available
- The demo scripts print the instance type, architecture and capacity type actually chosen

### Step 4: Verify Instance Family Selection
```bash
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
ARCH:.metadata.labels.kubernetes\\.io/arch,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type
```

Expected: Different instance families selected for each workload type

### Step 5: View Pod Distribution
```bash
kubectl get pods -n demo-app -o wide
```

Expected: compute and memory pods on different instance families, matched to their requests

## Talking Points

- "We deployed two workloads with very different resource profiles"
- "Karpenter analyzed the CPU and memory requirements independently"
- "Each workload got an instance shaped for it, and we never named an instance type"
- "Graviton is in the mix too, because the NodePool allows arm64"
- "No manual instance type configuration — Auto Mode figured it out"
- "This avoids over-provisioning: you don't pay for memory you don't need on compute nodes, or CPU you don't need on memory nodes"

## Key Metrics
- Node Provisioning Time: 45-60 seconds (sub-minute)
- Cost Optimization: 30-50% savings vs. manual one-size-fits-all selection
- Instance Families: Automatically selects from c, m, r (100+ instance types)
- Configuration Required: Zero
