output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "region" {
  description = "AWS region of the cluster"
  value       = var.aws_region
}

output "ssm_access_instance_id" {
  description = "SSM access host used by scripts/tunnel.sh to reach the private API endpoint"
  value       = aws_instance.ssm_access.id
}

output "configure_kubectl" {
  description = "Commands to point kubectl at the cluster (through the SSM tunnel when the endpoint is private)"
  value = var.endpoint_public_access ? "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}" : join("\n", [
    "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}",
    "kubectl config set-cluster ${module.eks.cluster_arn} --server=https://127.0.0.1:8443 --tls-server-name=${trimprefix(module.eks.cluster_endpoint, "https://")}",
  ])
}
