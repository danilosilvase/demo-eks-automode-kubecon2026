# EKS Auto Mode Demo: KubeCon 2026

Booth demo showing Amazon EKS Auto Mode cost optimization with EC2 Spot and AWS Graviton, on Kubernetes 1.37.

**What "zero config" means here.** On plain Kubernetes you install Karpenter, configure it, tune consolidation and keep upgrading it. With EKS Auto Mode, Karpenter is managed by AWS and runs with best-practice defaults, so you deploy a pod and get a node. Choosing Spot and Graviton is one NodePool on top of that.

## Demo Flow

| Step | What happens | What the audience sees |
|------|-------------|----------------------|
| 1. Zero config | Deploy an app, Auto Mode's managed Karpenter launches a node | Timer: node and pods ready |
| 2. Spot + Graviton NodePool | Apply one NodePool allowing Spot/On-Demand and amd64/arm64 | eks-node-viewer shows capacity type and architecture |
| 3. CPU-intensive workload | Deploy 2-core pods | The instance Karpenter picked, read live from the node labels |
| 4. Memory-intensive workload | Deploy 8Gi pods | The instance Karpenter picked, read live from the node labels |
| 5. Same app, Graviton | Same multi-arch nginx image, pinned to arm64 | A Graviton node, no image rebuild |
| 6. Sub-minute scaling | Scale to 30 replicas | Timer: new node and all pods ready |
| 7. Consolidation | Scale down | Timer: unused nodes removed |

## Requirements

### AWS Account

- Permissions to create: EKS clusters, VPCs, NAT Gateways, IAM roles
- AWS CLI configured (`aws sts get-caller-identity` should succeed)
- Region: us-west-2 (Oregon) with Spot and On-Demand quota for about 8 vCPUs

### CLI Tools

| Tool | Install |
|------|---------|
| AWS CLI v2 | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform >= 1.0 | `brew install terraform` |
| kubectl >= 1.28 | `brew install kubectl` |
| tmux | `brew install tmux` or your Linux package manager |
| eks-node-viewer | `brew install aws/tap/eks-node-viewer` or the Linux release binary |

Or run `./scripts/setup-tools.sh`. On macOS it uses Homebrew. On Linux, including the EKS Workshop browser IDE, it installs tmux with the package manager and downloads the eks-node-viewer release binary to `~/.local/bin`.

### Cost

About $1-3 USD for a 1-hour demo session.

## Quick Start

### 1. Deploy infrastructure (~10 min)

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Creates a VPC and an EKS cluster with Auto Mode enabled.

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --region us-west-2 --name eks-auto-demo
```

### 3. Launch the booth layout

```bash
./scripts/demo-visual.sh
```

Opens a two-pane tmux session sized to the current terminal:

```
┌─────────────────────────────────────────┐
│  eks-node-viewer (22 rows)              │
│  nodes, instance type, Spot/On-Demand,  │
│  arm64/amd64, price per node            │
├─────────────────────────────────────────┤
│  Command terminal                       │
└─────────────────────────────────────────┘
```

eks-node-viewer auto-restarts if it crashes (known issue with 0 nodes). Re-attach with `tmux attach-session -t eks-demo`.

To run it without tmux, start these in two terminals:

```bash
eks-node-viewer --node-sort=creation --extra-labels karpenter.sh/capacity-type,kubernetes.io/arch
./scripts/demo-commands.sh
```

### 4. Run the demo

```bash
# Interactive: step through manually
./scripts/demo-commands.sh

# Auto-run: for the silent, captioned booth recording
./scripts/demo-record.sh
```

Interactive prompt:
```
1:provision  2:spot+graviton  3:cpu  4:memory  5:graviton  6:scale  7:consolidate  c:clean  q:quit
>> 1
```

Type the number. Each step clears the screen and hints the next one. Type `c` anytime to reset, `h` for the menu.

### 5. Recording mode

Start screen recording, then:

```bash
./scripts/demo-record.sh          # 10s pauses (default)
PAUSE=5 ./scripts/demo-record.sh  # faster
PAUSE=15 ./scripts/demo-record.sh # slower
```

Runs all 7 steps with simulated typing, live timers and one caption per step. Captions only show numbers measured during the run.

## Running on the EKS Workshop cluster (booth live backup)

The demo also runs on the EKS Workshop Auto Mode cluster. The workshop's Auto Mode setup creates the `default` NodeClass that the `cost-optimized` NodePool references, so the manifests apply unchanged. That cluster runs Kubernetes 1.35; the demo steps behave the same.

```bash
git clone https://github.com/danilosilvase/demo-eks-automode-kubecon2026
cd demo-eks-automode-kubecon2026
./scripts/setup-tools.sh
export PATH="$HOME/.local/bin:$PATH"
./scripts/demo-visual.sh "${EKS_CLUSTER_AUTO_NAME}" "${AWS_REGION}"
```

## Resetting the demo

From the interactive prompt, type `c`. This:
- Deletes the `demo-app` namespace (all workloads)
- Removes the `cost-optimized` NodePool
- Waits for nodes to drain

Then start fresh from step 1.

## Use Case Documentation

1. [Spot Integration](docs-use-case-1-spot-integration.md): custom NodePool with Spot + On-Demand
2. [Intelligent Instance Selection](docs-use-case-2-intelligent-selection.md): instance family follows the pod's CPU-to-memory ratio
3. [Consolidation](docs-use-case-3-consolidation.md): automatic node removal on scale-down
4. [Sub-minute Scaling](docs-use-case-4-sub-minute-scaling.md): new capacity on a traffic spike

Additional:
- [Business Summary](DEMO-BUSINESS-SUMMARY.md)
- [Technical Guide](docs-technical-guide.md)

## Project Structure

```
.
├── terraform/
│   ├── main.tf                 # EKS cluster with Auto Mode
│   ├── cloudwatch.tf           # Container Insights + dashboard (disabled)
│   ├── variables.tf / outputs.tf / versions.tf
├── cloudwatch/
│   ├── dashboard.json          # CloudWatch dashboard definition
│   ├── deploy-dashboard.sh     # Standalone deploy
│   └── cleanup-dashboard.sh
├── manifests/
│   ├── 00-cost-optimized-nodepool.yaml     # Spot + On-Demand, amd64 + arm64
│   ├── 01-namespace.yaml
│   ├── 02-sample-app.yaml                  # 3 replicas, nginx (ECR Public)
│   ├── 03-compute-intensive-workload.yaml  # 2 CPU cores/pod, multi-arch stress-ng
│   ├── 04-memory-intensive-workload.yaml   # 8Gi memory/pod, multi-arch stress-ng
│   ├── 05-load-generator.yaml
│   ├── 06-pod-disruption-budget.yaml
│   └── 07-graviton-workload.yaml           # same nginx image, pinned to arm64
├── scripts/
│   ├── setup-tools.sh          # Install tmux + eks-node-viewer (macOS or Linux)
│   ├── demo-visual.sh          # Launch the two-pane booth layout
│   ├── demo-commands.sh        # Interactive demo runner
│   └── demo-record.sh          # Auto-run for the captioned recording
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

About 4 minutes.
