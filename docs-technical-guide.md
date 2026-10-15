# EKS Auto Mode Demo: Technical Guide

## Infrastructure Setup (~10 min)

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
aws eks update-kubeconfig --region us-west-2 --name eks-auto-demo
```

Creates: VPC, NAT Gateway, EKS cluster with Auto Mode (Kubernetes 1.37).

Result: cluster ready with 0 nodes. Nodes launch when workloads need them.

## Demo Flow

### Step 1: Zero config

Deploy the namespace and sample app. Auto Mode's managed Karpenter launches a node.

```bash
kubectl apply -f manifests/01-namespace.yaml
kubectl apply -f manifests/02-sample-app.yaml
```

The live timer shows node and pod readiness.

Talking point: "No Karpenter to install, configure or upgrade. Deploy a workload, get a node."

### Step 2: Spot + Graviton NodePool

Apply the custom `cost-optimized` NodePool. It allows Spot and On-Demand, and both amd64 and arm64 (AWS Graviton).

```bash
kubectl apply -f manifests/00-cost-optimized-nodepool.yaml
```

The built-in Auto Mode NodePools are On-Demand only. This NodePool has a higher weight, so Karpenter prefers it and replaces the On-Demand node with Spot. The live timer tracks the Spot node.

Talking point: "Spot and Graviton are one NodePool. Karpenter is already running."

### Step 3: CPU-intensive workload

Deploy 2 replicas with 2 CPU cores each.

```bash
kubectl apply -f manifests/03-compute-intensive-workload.yaml
```

Karpenter picks the cheapest instance that fits a high CPU-to-memory ratio. The script prints the instance type, architecture and capacity type it actually chose.

Talking point: "We never named an instance type. Karpenter read the pod requests."

### Step 4: Memory-intensive workload

Deploy 2 replicas with 8Gi memory each.

```bash
kubectl apply -f manifests/04-memory-intensive-workload.yaml
```

The script prints the instance Karpenter chose for the memory-heavy pods.

Talking point: "Different workload shape, different instance, same NodePool."

### Step 5: Same app, Graviton

Deploy the same nginx image as the sample app, pinned to arm64.

```bash
kubectl apply -f manifests/07-graviton-workload.yaml
```

The image is multi-arch, so nothing is rebuilt. Karpenter launches a Graviton node, Spot when available.

Talking point: "Same container image, now on Graviton. One line in the pod spec."

### Step 6: Sub-minute scaling

Scale the sample app to 30 replicas.

```bash
kubectl scale deployment sample-app --replicas=30 -n demo-app
```

The live timer tracks the new node and pod readiness.

Talking point: "Traffic spike, new capacity in under a minute."

### Step 7: Consolidation

Scale the CPU, memory and Graviton workloads to 0 and the sample app back to 3.

```bash
kubectl scale deployment compute-intensive --replicas=0 -n demo-app
kubectl scale deployment memory-intensive --replicas=0 -n demo-app
kubectl scale deployment sample-app-graviton --replicas=0 -n demo-app
kubectl scale deployment sample-app --replicas=3 -n demo-app
```

The live timer tracks node removal.

Talking point: "Nodes nobody needs are drained and removed. You stop paying for them."

## Visual Tools

| Tool | Pane | Shows |
|------|------|-------|
| eks-node-viewer | tmux top (22 rows) | Node bars, instance types, Spot/On-Demand, arm64/amd64, price per node |
| Command terminal | tmux bottom | Demo steps, timers, captions |

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

If the live demo fails, play the captioned recording made with `./scripts/demo-record.sh`.
