# EKS Auto Mode demo v4 (KubeCon NA 2026)

Version 4 of the demo follows the deck "Auto Mode Cost Optimization": six core steps, plus Graviton as an optional bonus.
It runs in two styles from the same script (`scripts/demo-v4.sh`):

- **Labelled**: step banner, captions, a running results tally, timers, node join/remove events, recap card.
- **Clean**: the same steps and the real `kubectl` commands only, as if typed on a laptop.

Every number on screen is read live from the cluster or from eks-node-viewer. Instance types and timings change from run to run, because Auto Mode picks the cheapest fit at that moment.

## Steps and keys

| Key | Step | What it shows |
|---|---|---|
| 1 | Zero config | Pending pods, then the NodeClaim Auto Mode created, then the node. Nothing installed. |
| 2 | Spot | One NodePool allows Spot and On-Demand. The app moves from On-Demand to Spot, with both prices. |
| 3 | CPU | 2 pods × 2 vCPU. Auto Mode picks an instance that fits. Measured NodeClaim-to-Ready time. |
| 4 | Memory | 2 pods × 8 GiB. Same NodePool, different instance. |
| 5 | Burst | Scale the app from 3 to 30 pods. Nodes added (and any removed meanwhile). |
| 6 | Consolidation | Scale down. Under-used nodes are drained and removed; $/hour drops. |
| g | Graviton (bonus) | Same Deployment and multi-arch image pinned to arm64. The caption says whether a new Graviton node launched or the pods moved onto an existing one. |
| r | Recap | Every result measured in this run. |
| c | Reset | Deletes the demo namespace and NodePool, waits for 0 nodes. |
| q | Quit | |

In the live menu, Enter on its own runs the suggested next step.

Graviton is a bonus because it is not guaranteed to show a *new* node: if Auto Mode already picked a Graviton node as the cheapest fit in an earlier step, the pods simply move onto it.

The consolidation step states the policy used: the demo NodePool (`manifests/00-cost-optimized-nodepool.yaml`) sets `WhenEmptyOrUnderutilized` with `consolidateAfter: 30s`. Auto Mode's built-in NodePools use `Balanced`.

## Run it

Prerequisites: an EKS Auto Mode cluster (see `terraform/`), `kubectl`, `tmux`, `eks-node-viewer` (`./scripts/setup-tools.sh`), and a kubeconfig that reaches the cluster.

```bash
./scripts/reset-demo.sh                 # start from 0 nodes
./scripts/live-v4.sh                    # live, labelled
CLEAN=1 ./scripts/live-v4.sh            # live, clean
./scripts/booth-v4.sh                   # unattended loop (booth screen), labelled
BONUS=1 ./scripts/booth-v4.sh           # loop including the Graviton step
```

## Recordings

`recordings/demo-v4-labelled.mp4` and `recordings/demo-v4-clean.mp4`: full real-time runs (about 11 to 13 minutes), recorded in us-west-2 on EKS 1.37, with the Graviton bonus at the end.

## Notes for presenting

- `$/hour` is the EC2 instance price shown by eks-node-viewer. It excludes the EKS Auto Mode fee and the control plane.
- The scale-down step takes about 2 minutes (30s `consolidateAfter`, then drain). Talk over it.
- Earlier iterations (`scripts/demo-record-v2.sh`, `scripts/demo-record-v3.sh`) are kept for comparison. The original `scripts/demo-commands.sh` menu is unchanged.
