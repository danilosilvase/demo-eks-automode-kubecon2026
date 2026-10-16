# EKS Auto Mode Demo: KubeCon 2026

Booth and live demo of Amazon EKS Auto Mode cost optimization: Spot, right-sized instances, sub-minute scaling and consolidation, with a Graviton bonus. Kubernetes 1.37.

**What "zero config" means here.** On plain Kubernetes you install Karpenter, configure it, tune consolidation and keep upgrading it. With EKS Auto Mode, Karpenter is managed by AWS and runs with best-practice defaults, so you deploy a pod and get a node. Choosing Spot and Graviton is one NodePool on top of that.

## What the demo shows

| Step | What you run | What the audience sees |
|------|--------------|------------------------|
| 1. Zero config | Deploy a 3-replica app | Pending pods, a NodeClaim, then a node and running pods (timer) |
| 2. Spot | Apply one NodePool allowing Spot and On-Demand, amd64 and arm64 | Auto Mode replacing the On-Demand node with a cheaper Spot node, with both prices |
| 3. CPU-intensive | Deploy 2-core pods | The instance family Auto Mode picked for that CPU-to-memory ratio |
| 4. Memory-intensive | Deploy 8Gi pods | The instance family Auto Mode picked for a memory-heavy ratio |
| 5. Burst | Scale to 30 replicas | Nodes added and all pods running (timer) |
| 6. Consolidation | Scale back down | Unused nodes removed and the $/hour drop (timer) |
| Bonus g. Graviton | Same multi-arch image pinned to arm64 | Pods on Graviton with no image rebuild |

Every number on screen is read live from the cluster or from the eks-node-viewer pane. Nothing is hard-coded.

## Recordings

Pre-recorded runs, for the booth screen or as a backup if the network fails:

- [`recordings/demo-labelled.mp4`](recordings/demo-labelled.mp4) (9:38): captions, step banner, results tally and recap.
- [`recordings/demo-clean.mp4`](recordings/demo-clean.mp4) (11:34): plain kubectl, as if typed on a laptop.

## Prerequisites

- An AWS account where you can create a VPC, NAT gateway, EKS cluster, IAM roles and a small EC2 instance, in a region with Spot and On-Demand quota for about 8 vCPUs (default `us-west-2`).
- Tools: AWS CLI v2, Session Manager plugin, Terraform >= 1.0, kubectl, tmux, eks-node-viewer. `./scripts/setup-tools.sh` installs tmux and eks-node-viewer on macOS (Homebrew) or Linux (including the EKS Workshop browser IDE) and checks the rest.

**Cost.** The cluster control plane, the NAT gateway and the t4g.nano access host bill for as long as the stack exists, and worker nodes bill while the demo runs. Destroy the stack when you are done (see [Teardown](#teardown)).

## 1. Deploy (about 10 minutes)

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Creates a VPC (private subnets, one NAT gateway), an EKS Auto Mode cluster with the built-in `general-purpose` and `system` node pools, and a small SSM access host.

**Nothing is exposed publicly.** The API endpoint is private by default (`endpoint_public_access = false`). The access host has no public IP and no inbound rules; you reach the API through an AWS Systems Manager port-forward. If you prefer a public endpoint, set `endpoint_public_access = true` and limit `endpoint_public_access_cidrs` to your own IP.

## 2. Connect kubectl

Start the tunnel in its own terminal and leave it running:

```bash
./scripts/tunnel.sh        # localhost:8443 -> private EKS API endpoint
```

Then, once, point kubectl at it:

```bash
terraform -chdir=terraform output -raw configure_kubectl   # prints the two commands below, filled in
aws eks update-kubeconfig --name eks-auto-demo --region us-west-2
kubectl config set-cluster <cluster-arn> --server=https://127.0.0.1:8443 --tls-server-name=<endpoint-host>
kubectl get --raw /readyz
```

## 3. Run

Start from an empty cluster:

```bash
./scripts/reset-demo.sh            # deletes the demo namespace and NodePool, waits for 0 nodes
```

**Live, with a presenter menu:**

```bash
./scripts/live.sh                  # captions, step banner, results tally
CLEAN=1 ./scripts/live.sh          # plain kubectl, no captions
```

| Key | Action |
|-----|--------|
| Enter | Run the suggested next step |
| 1-6 | Run a step |
| g | Graviton bonus |
| r | Recap of the numbers measured so far |
| c | Reset to 0 nodes |
| q | Quit |

**Unattended loop, for the booth screen or a recording:**

```bash
./scripts/booth.sh                 # steps 1-6, then the recap
BONUS=1 ./scripts/booth.sh         # adds the Graviton step
CLEAN=1 PAUSE=5 ./scripts/booth.sh # plain kubectl, shorter pauses
```

Both open a two-pane tmux session: eks-node-viewer on top (nodes, Spot or On-Demand, architecture, $/hour), the demo below. Detach with `Ctrl+B` then `D`; re-attach with `tmux -L ekrec attach -t eks-rec`.

## Presenting notes

- **$/hour is the EC2 instance price** shown by eks-node-viewer. It excludes the EKS Auto Mode fee and the control plane.
- **Instance types vary run to run.** Auto Mode picks the cheapest fit at that moment, so say "a Spot c-family node", not a specific type.
- **Consolidation policy.** The built-in node pools use the `Balanced` policy. The demo's `cost-optimized` NodePool uses `WhenEmptyOrUnderutilized` with `consolidateAfter: 30s`, which is why underutilized nodes go quickly in step 6.
- **Graviton is a bonus.** With arm64 allowed in step 2, Auto Mode often picks Graviton Spot on its own, so step g may reuse an existing node instead of launching one. The caption reports what really happened.

## Running on the EKS Workshop cluster

The demo also runs on the EKS Workshop Auto Mode cluster. The workshop's Auto Mode setup creates the `default` NodeClass that the `cost-optimized` NodePool references, so the manifests apply unchanged. That cluster runs Kubernetes 1.35; the steps behave the same. kubectl is already configured there, so skip the tunnel:

```bash
git clone https://github.com/danilosilvase/demo-eks-automode-kubecon2026
cd demo-eks-automode-kubecon2026
./scripts/setup-tools.sh
export PATH="$HOME/.local/bin:$PATH"
./scripts/live.sh
```

## Teardown

```bash
./scripts/reset-demo.sh                    # let Auto Mode remove the worker nodes first
tmux -L ekrec kill-server 2>/dev/null
terraform -chdir=terraform destroy
```

## Repository layout

```
.
├── manifests/
│   ├── 00-cost-optimized-nodepool.yaml     # Spot + On-Demand, amd64 + arm64, c/m/r families
│   ├── 01-namespace.yaml
│   ├── 02-sample-app.yaml                  # 3 replicas, nginx (ECR Public, multi-arch)
│   ├── 03-compute-intensive-workload.yaml  # 2 CPU cores per pod
│   ├── 04-memory-intensive-workload.yaml   # 8Gi memory per pod
│   └── 06-pod-disruption-budget.yaml
├── recordings/                             # demo-labelled.mp4, demo-clean.mp4
├── scripts/
│   ├── live.sh                             # live presenter menu
│   ├── booth.sh                            # tmux layout + unattended loop
│   ├── demo.sh                             # the demo steps (started by live.sh / booth.sh)
│   ├── reset-demo.sh                       # back to 0 nodes
│   ├── tunnel.sh                           # SSM port-forward to the private API
│   ├── setup-tools.sh                      # tmux + eks-node-viewer install
│   └── tmux-truecolor.conf                 # 24-bit colour for the node-viewer bars
└── terraform/
    ├── main.tf                             # VPC + EKS Auto Mode cluster
    ├── private-access.tf                   # SSM access host for the private endpoint
    └── variables.tf / outputs.tf / versions.tf
```

## Learn more

- [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Create a node pool for EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/create-node-pool.html)
- [eks-node-viewer](https://github.com/awslabs/eks-node-viewer)
