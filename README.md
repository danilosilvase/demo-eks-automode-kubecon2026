# EKS Auto Mode Demo — KubeCon 2026

Live demo showcasing EKS Auto Mode cost optimization on Kubernetes 1.35.

## Demo Flow

| Step | What happens | What the audience sees |
|------|-------------|----------------------|
| 1. Zero-config provisioning | Deploy app, node appears automatically | ⏱ Timer: node + pods ready in ~60s |
| 2. Spot NodePool | Apply one manifest, nodes switch to Spot | eks-node-viewer shows Spot label |
| 3. CPU-intensive workload | Deploy 2-core pods | c-family instance selected |
| 4. Memory-intensive workload | Deploy 8Gi pods | r-family instance selected |
| 5. Consolidation | Scale down, nodes drain | ⏱ Timer: nodes removed in ~60s |
| 6. Sub-minute scaling | Scale to 30 replicas | ⏱ Timer: new node in <60s |

## Requirements

### AWS Account

- Permissions to create: EKS clusters, VPCs, NAT Gateways, IAM roles, CloudWatch dashboards, EKS addons
- AWS CLI configured (`aws sts get-caller-identity` should succeed)
- Region: eu-central-1 with sufficient quotas (~8 vCPUs on-demand + Spot)

### CLI Tools

| Tool | Install |
|------|---------|
| AWS CLI v2 | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform >= 1.0 | `brew install terraform` |
| kubectl >= 1.28 | `brew install kubectl` |
| tmux | `brew install tmux` |
| k9s | `brew install derailed/k9s/k9s` |
| eks-node-viewer | `brew install aws/tap/eks-node-viewer` |

Or run `./scripts/setup-tools.sh` to install tmux, k9s, and eks-node-viewer.

### Local Environment

- macOS or Linux (bash)
- Terminal at least 200 columns wide
- ~2 GB free disk space

### Cost

~$1-3 USD for a 1-hour demo session.

## Quick Start

### 1. Deploy infrastructure (~10 min)

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Creates VPC, EKS cluster with Auto Mode, Container Insights addon, and CloudWatch dashboard.

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --region eu-central-1 --name eks-auto-demo
```

### 3. Launch visual layout

```bash
./scripts/demo-visual.sh
```

Opens a tmux session:

```
┌─────────────────────────────────────────┐
│      eks-node-viewer (14 rows)          │
│  node bars, instance types, Spot/OD     │
├──────────────┬──────────────────────────┤
│              │                          │
│  k9s (pods)  │    Command terminal      │
│              │    (60% width)           │
│              │                          │
└──────────────┴──────────────────────────┘
```

eks-node-viewer auto-restarts if it crashes (known issue with 0 nodes).

### 4. Open CloudWatch dashboard

```
https://eu-central-1.console.aws.amazon.com/cloudwatch/home?region=eu-central-1#dashboards/dashboard/EKS-AutoMode-Demo-eks-auto-demo
```

### 5. Run the demo

From the command terminal pane:

```bash
# Interactive — step through manually
./scripts/demo-commands.sh

# Auto-run — for screen recording
./scripts/demo-record.sh
```

Interactive prompt:
```
1:provision  2:spot  3:cpu  4:memory  5:consolidate  6:scale  c:clean  q:quit
>> 1
```

Type the number, each step clears the screen. After each step it hints the next one. Type `c` anytime to reset. Type `h` for the full menu.

### 6. Recording mode

Start screen recording, then:

```bash
./scripts/demo-record.sh          # 10s pauses (default)
PAUSE=5 ./scripts/demo-record.sh  # faster
PAUSE=15 ./scripts/demo-record.sh # slower
```

Runs all 6 steps with simulated typing and live timers.

## Resetting the demo

From the interactive prompt, type `c`. This:
- Deletes the `demo-app` namespace (all workloads)
- Removes the `cost-optimized` NodePool
- Waits for nodes to drain

Then start fresh from step 1.

## Use Case Documentation

1. [Spot Integration](docs-use-case-1-spot-integration.md) — Custom NodePool with Spot + On-Demand
2. [Intelligent Instance Selection](docs-use-case-2-intelligent-selection.md) — c-family for CPU, r-family for memory
3. [Consolidation](docs-use-case-3-consolidation.md) — Automatic node removal on scale-down
4. [Sub-Minute Scaling](docs-use-case-4-sub-minute-scaling.md) — Node provisioning in <60s

Additional:
- [Business Summary](DEMO-BUSINESS-SUMMARY.md)
- [Technical Guide](docs-technical-guide.md)

## Project Structure

```
.
├── terraform/
│   ├── main.tf                 # EKS cluster with Auto Mode
│   ├── cloudwatch.tf           # Container Insights + dashboard
│   ├── variables.tf / outputs.tf / versions.tf
├── cloudwatch/
│   ├── dashboard.json          # CloudWatch dashboard definition
│   ├── deploy-dashboard.sh     # Standalone deploy
│   └── cleanup-dashboard.sh
├── manifests/
│   ├── 00-cost-optimized-nodepool.yaml  # Spot + On-Demand NodePool
│   ├── 01-namespace.yaml
│   ├── 02-sample-app.yaml               # 3 replicas, nginx
│   ├── 03-compute-intensive-workload.yaml  # 2 CPU cores/pod
│   ├── 04-memory-intensive-workload.yaml   # 8Gi memory/pod
│   ├── 05-load-generator.yaml
│   └── 06-pod-disruption-budget.yaml
├── scripts/
│   ├── setup-tools.sh          # Install visualization tools
│   ├── demo-visual.sh          # Launch tmux layout
│   ├── demo-commands.sh        # Interactive demo runner
│   └── demo-record.sh          # Auto-run for recording
└── docs-*.md
```

## Teardown

```bash
# Kill tmux
tmux kill-session -t eks-demo

# Destroy infrastructure
cd terraform
terraform destroy -auto-approve
```

~4 minutes.
