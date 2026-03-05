# Use Case 1: Spot Instance Integration

## Business Value
Reduce compute costs by up to 90% through automatic Spot instance utilization without application changes or manual configuration.

## How It Works

EKS Auto Mode's built-in `general-purpose` NodePool uses on-demand only. To enable Spot, we create a custom `cost-optimized` NodePool with `weight: 100` (higher than the built-in pool's default) so Karpenter prefers it for scheduling. The pool allows both `spot` and `on-demand` capacity types — Karpenter automatically selects Spot when available for cost savings, falling back to on-demand if needed.

The manifest is at `manifests/00-cost-optimized-nodepool.yaml` and is applied during setup.

Reference: [Create a Node Pool for EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/create-node-pool.html)

## Demo Steps (2-3 minutes)

### Step 1: View Current Nodes with Capacity Types
```bash
kubectl get nodes -L karpenter.sh/capacity-type,karpenter.sh/nodepool,node.kubernetes.io/instance-type
```
Expected: Shows nodes with a mix of `spot` and `on-demand` capacity types

### Step 2: View All NodePools
```bash
kubectl get nodepools
```
Expected: Shows `cost-optimized`, `general-purpose`, and `system` pools

### Step 3: Inspect the Cost-Optimized NodePool
```bash
kubectl describe nodepool cost-optimized
```

Key information to highlight:
- Weight: 100 (higher priority than built-in pools)
- Capacity Types: spot, on-demand (Karpenter prefers Spot for cost)
- Instance Families: c, m, r
- Consolidation Policy: WhenEmptyOrUnderutilized (30s)

### Step 4: Show Capacity Type Breakdown
```bash
echo "On-Demand: $(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers | wc -l)"
echo "Spot:      $(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers | wc -l)"
```

## Talking Points

- "We created a single custom NodePool — that's all it takes to enable Spot"
- "Karpenter automatically selects Spot when available, falls back to on-demand"
- "No application changes needed — pods don't know or care about capacity type"
- "The built-in general-purpose pool stays as a safety net for on-demand"
- "Spot instances provide up to 90% cost savings with automatic interruption handling"
- "Watch eks-node-viewer — you can see Spot vs On-Demand in real-time"

## Key Metrics
- Cost Savings: Up to 90% reduction on compute costs
- Configuration: One custom NodePool manifest
- Interruption Handling: Automatic — Karpenter replaces interrupted Spot nodes
- Fallback: Automatic to on-demand if Spot unavailable
