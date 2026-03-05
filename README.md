# EKS Auto Mode Demo — KubeCon 2026

Demo showcasing EKS Auto Mode cost optimization features on Kubernetes 1.35.

## Requirements

### AWS Account & Permissions

- An AWS account with permissions to create: EKS clusters, VPCs, NAT Gateways, IAM roles, CloudWatch dashboards, and EKS addons
- AWS CLI configured and authenticated (`aws sts get-caller-identity` should succeed)
- Sufficient service quotas in the target region (eu-central-1):
  - EKS clusters: at least 1 available
  - VPCs: at least 1 available
  - Elastic IPs: at least 1 available (for NAT Gateway)
  - EC2 instances: on-demand vCPU limit sufficient for demo workloads (~8 vCPUs)

### CLI Tools

| Tool | Min Version | Install |
|------|-------------|---------|
| AWS CLI | v2.x | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform | >= 1.0 | `brew install terraform` |
| kubectl | >= 1.28 | `brew install kubectl` |
| tmux | any | `brew install tmux` |
| k9s | any | `brew install derailed/k9s/k9s` |
| eks-node-viewer | any | `brew install aws/tap/eks-node-viewer` |
| Homebrew | any | [brew.sh](https://brew.sh) (macOS) |

Run `./scripts/setup-tools.sh` to check and install tmux, k9s, and eks-node-viewer automatically.

### Local Environment

- macOS or Linux (scripts use bash)
- Internet access (Terraform providers, container images, CloudWatch API)
- ~2 GB free disk space (Terraform provider cache)
- A terminal that supports at least 200 columns wide (for the tmux layout)

### Estimated Costs

- EKS cluster: ~$0.10/hr
- NAT Gateway: ~$0.045/hr + data transfer
- EC2 nodes (Auto Mode managed): varies by instance type, typically 1-3 nodes during demo
- CloudWatch Container Insights: ~$0.01/metric/month
- Total for a 1-hour demo session: approximately $1-3 USD

### Time Requirements

| Phase | Duration |
|-------|----------|
| Tool installation | ~5 min (first time only) |
| Cluster creation (`terraform apply`) | ~10 min |
| Application deployment | ~2 min |
| Live demo | 12-15 min |
| Cleanup (`terraform destroy`) | ~4 min |

## Quick Start

### 1. Install Visualization Tools

```bash
./scripts/setup-tools.sh
```

### 2. Deploy Cluster

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Takes ~10 minutes. Creates VPC, NAT Gateway, EKS cluster with Auto Mode, Container Insights addon, and CloudWatch dashboard.

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --region eu-central-1 --name eks-auto-demo
```

### 4. Deploy Applications

```bash
kubectl apply -f manifests/00-cost-optimized-nodepool.yaml
kubectl apply -f manifests/01-namespace.yaml
kubectl apply -f manifests/02-sample-app.yaml
```

Wait ~60 seconds for first node to provision (should come up as Spot).

### 5. Launch Visual Demo

```bash
./scripts/demo-visual.sh
```

This opens a tmux session with three panes:

```
┌─────────────────────────────────────────┐
│      eks-node-viewer (compact)          │
│  (node utilization bars + costs)        │
├──────────────┬──────────────────────────┤
│              │                          │
│  k9s (pods)  │    Command terminal      │
│              │    (wider, for output)    │
│              │                          │
└──────────────┴──────────────────────────┘
```

Then open the CloudWatch dashboard in a browser (URL printed during `terraform apply` or by running `./cloudwatch/deploy-dashboard.sh`).

### 6. Run Demo Commands

From the command terminal pane inside tmux:

```bash
./scripts/demo-commands.sh
```

Interactive menu lets you run each demo part. The other panes update in real-time.

## Visualization Stack

| Tool | What it shows | Where |
|------|--------------|-------|
| eks-node-viewer | Node utilization bars, instance types, capacity types | tmux top pane |
| k9s | Pod lifecycle (Pending → Running), real-time status | tmux bottom-left |
| CloudWatch Dashboard | Metrics over time: node count, CPU/memory, pod count | Browser tab |

### CloudWatch Dashboard

Deployed automatically via Terraform (`terraform/cloudwatch.tf`). Can also be deployed standalone:

```bash
# Deploy
./cloudwatch/deploy-dashboard.sh eks-auto-demo eu-central-1

# Cleanup
./cloudwatch/cleanup-dashboard.sh eks-auto-demo eu-central-1
```

Dashboard panels:
- Node Count Over Time (shows scaling and consolidation)
- Pod Count in demo-app namespace
- Cluster CPU and Memory Utilization
- CPU/Memory Reserved vs Used (shows right-sizing)
- Single-value gauges for current state

## Demo Use Cases

Each use case has detailed step-by-step instructions:

1. [Spot Instance Integration](docs-use-case-1-spot-integration.md) — Up to 90% cost savings (2-3 min)
2. [Intelligent Instance Selection](docs-use-case-2-intelligent-selection.md) — 30-50% savings (3-4 min)
3. [Continuous Consolidation](docs-use-case-3-consolidation.md) — 40-60% savings (4-5 min)
4. [Sub-Minute Scaling](docs-use-case-4-sub-minute-scaling.md) — Fast response to demand (2-3 min)

## Additional Documentation

- [Business Summary](DEMO-BUSINESS-SUMMARY.md) — Executive overview with ROI
- [Technical Guide](docs-technical-guide.md) — Complete demo guide with timings

## Project Structure

```
.
├── terraform/
│   ├── main.tf                 # EKS Auto Mode cluster
│   ├── cloudwatch.tf           # Container Insights addon + dashboard
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
├── cloudwatch/
│   ├── dashboard.json          # CloudWatch dashboard definition
│   ├── deploy-dashboard.sh     # Standalone dashboard deploy
│   └── cleanup-dashboard.sh    # Dashboard cleanup
├── manifests/
│   ├── 01-namespace.yaml
│   ├── 02-sample-app.yaml
│   ├── 03-compute-intensive-workload.yaml
│   ├── 04-memory-intensive-workload.yaml
│   ├── 05-load-generator.yaml
│   └── 06-pod-disruption-budget.yaml
├── scripts/
│   ├── setup-tools.sh          # Install eks-node-viewer, k9s, tmux
│   ├── demo-visual.sh          # Launch tmux visual layout
│   └── demo-commands.sh        # Interactive demo command runner
├── docs-use-case-*.md
├── docs-technical-guide.md
└── DEMO-BUSINESS-SUMMARY.md
```

## Cleanup

```bash
# Delete workloads
kubectl delete namespace demo-app

# Destroy infrastructure (includes CloudWatch dashboard)
cd terraform
terraform destroy -auto-approve

# Kill tmux session
tmux kill-session -t eks-demo
```

Takes ~4 minutes.
