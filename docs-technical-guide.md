# EKS Auto Mode Demo — Technical Guide

## Infrastructure Setup (~10 min)

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
aws eks update-kubeconfig --region eu-central-1 --name eks-auto-demo
```

Creates: VPC, NAT Gateway, EKS cluster (K8s 1.35), Container Insights addon, CloudWatch dashboard.

Result: Cluster ready, 0 nodes (nodes provision on workload demand).

## Demo Flow (12-15 min)

### Step 1: Zero-config provisioning (2-3 min)

Deploy namespace + sample app. Auto Mode provisions a node automatically.

```bash
kubectl apply -f manifests/01-namespace.yaml
kubectl apply -f manifests/02-sample-app.yaml
```

Live timer shows node + pod readiness. Expected: ~60s for node, ~70s for all 3 pods.

Talking point: "Zero configuration — deploy a workload, get a node."

### Step 2: Spot NodePool (2-3 min)

Apply the custom `cost-optimized` NodePool with Spot + On-Demand.

```bash
kubectl apply -f manifests/00-cost-optimized-nodepool.yaml
```

Karpenter consolidates existing on-demand node to Spot. Live timer tracks Spot node appearance.

Talking point: "One manifest — that's all it takes to enable Spot."

### Step 3: CPU-intensive workload (2-3 min)

Deploy 2 replicas × 2 CPU cores each.

```bash
kubectl apply -f manifests/03-compute-intensive-workload.yaml
```

Expected: Karpenter provisions a c-family (compute-optimized) Spot instance.

Talking point: "High CPU demand → c-family instance, automatically."

### Step 4: Memory-intensive workload (2-3 min)

Deploy 2 replicas × 8Gi memory each.

```bash
kubectl apply -f manifests/04-memory-intensive-workload.yaml
```

Expected: Karpenter provisions an r-family (memory-optimized) Spot instance.

Talking point: "High memory demand → r-family instance. Different workload, different instance."

### Step 5: Consolidation (3-4 min)

Scale down compute + memory workloads to 0.

```bash
kubectl scale deployment compute-intensive --replicas=0 -n demo-app
kubectl scale deployment memory-intensive --replicas=0 -n demo-app
```

Live timer tracks node removal. Expected: ~60-90s for full consolidation.

Talking point: "Nodes drain automatically — 40-60% savings during off-peak."

### Step 6: Sub-minute scaling (2-3 min)

Scale sample-app to 30 replicas.

```bash
kubectl scale deployment sample-app --replicas=30 -n demo-app
```

Live timer tracks new node provisioning. Expected: <60s for new node, ~75s for all pods.

Talking point: "Traffic spike → new capacity in under a minute."

## Timing Summary

| Step | Action | Expected Time |
|------|--------|--------------|
| 1. Provision | Deploy app → node + pods ready | ~60-70s |
| 2. Spot | Apply NodePool → Spot node appears | ~60-90s |
| 3. CPU workload | Deploy → c-family node ready | ~45-60s |
| 4. Memory workload | Deploy → r-family node ready | ~45-60s |
| 5. Consolidation | Scale down → nodes removed | ~60-90s |
| 6. Scaling | Scale to 30 → new node + all pods | ~60-75s |

## Visual Tools

| Tool | Pane | Shows |
|------|------|-------|
| eks-node-viewer | tmux top (14 rows) | Node bars, instance types, Spot/OD, cost |
| k9s | tmux bottom-left | Pod lifecycle, status, namespace view |
| CloudWatch | Browser tab | Node count, CPU/memory, pod count over time |

## Cleanup

```bash
# From interactive demo: type 'c'
# Or manually:
kubectl delete namespace demo-app
kubectl delete nodepool cost-optimized
```

## Teardown

```bash
cd terraform
terraform destroy -auto-approve  # ~4 min
tmux kill-session -t eks-demo
```

## Backup Plan

If live demo fails:
1. Pre-recorded terminal session via `./scripts/demo-record.sh`
2. CloudWatch dashboard screenshots
3. Key metrics to reference: provisioning <60s, consolidation ~90s
