# EKS Auto Mode Demo - KubeCon 2026

Demo showcasing EKS Auto Mode cost optimization features on Kubernetes 1.35.

## Quick Start

### Prerequisites
- AWS CLI configured
- Terraform >= 1.0
- kubectl

### 1. Deploy Cluster

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Takes ~10 minutes. Creates VPC, NAT Gateway, and EKS cluster with Auto Mode.

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --region eu-central-1 --name eks-auto-demo
```

### 3. Deploy Applications

```bash
kubectl apply -f manifests/01-namespace.yaml
kubectl apply -f manifests/02-sample-app.yaml
```

Wait ~60 seconds for first node to provision.

## Demo Use Cases

Each use case has detailed step-by-step instructions:

1. [Spot Instance Integration](docs-use-case-1-spot-integration.md) - Up to 90% cost savings (2-3 min)
2. [Intelligent Instance Selection](docs-use-case-2-intelligent-selection.md) - 30-50% savings (3-4 min)
3. [Continuous Consolidation](docs-use-case-3-consolidation.md) - 40-60% savings (4-5 min)
4. [Sub-Minute Scaling](docs-use-case-4-sub-minute-scaling.md) - Fast response to demand (2-3 min)

## Additional Documentation

- [Business Summary](DEMO-BUSINESS-SUMMARY.md) - Executive overview with ROI
- [Technical Guide](docs-technical-guide.md) - Complete demo guide with timings

## Key Commands

```bash
# View cluster
kubectl get nodes
kubectl get nodepools

# View applications
kubectl get pods -n demo-app
kubectl get pods -n demo-app -o wide

# Scale workloads
kubectl scale deployment sample-app --replicas=10 -n demo-app
kubectl scale deployment compute-intensive --replicas=0 -n demo-app
```

## Cleanup

```bash
kubectl delete namespace demo-app
cd terraform
terraform destroy -auto-approve
```

Takes ~4 minutes.

## Project Structure

```
.
├── terraform/              # Infrastructure as Code
├── manifests/              # Kubernetes manifests
├── docs-use-case-*.md      # Step-by-step demo guides
├── DEMO-BUSINESS-SUMMARY.md
└── docs-technical-guide.md
```

## Cost Optimization Summary

- Spot Integration: Up to 90% savings
- Intelligent Selection: 30-50% savings
- Continuous Consolidation: 40-60% savings during off-peak
- Zero configuration required
- Kubernetes 1.35 (latest version)
