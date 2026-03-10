# =============================================================================
# CloudWatch Container Insights + Demo Dashboard
# =============================================================================
# Enables enhanced observability on the EKS cluster and deploys a
# pre-built CloudWatch dashboard for the live demo.
# =============================================================================

# --- Container Insights Addon (disabled for demo) ---
# resource "aws_eks_addon" "cloudwatch_observability" {
#   cluster_name = module.eks.cluster_name
#   addon_name   = "amazon-cloudwatch-observability"
#
#   # Let EKS pick the latest compatible version
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#
#   tags = var.tags
# }

# --- CloudWatch Dashboard (disabled for demo) ---
# resource "aws_cloudwatch_dashboard" "eks_demo" {
#   dashboard_name = "EKS-AutoMode-Demo-${var.cluster_name}"
#
#   dashboard_body = file("${path.module}/../cloudwatch/dashboard.json")
#
#
#   depends_on = [aws_eks_addon.cloudwatch_observability]
# }

# --- Outputs (disabled for demo) ---
# output "cloudwatch_dashboard_url" {
#   description = "URL to open the CloudWatch demo dashboard"
#   value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/EKS-AutoMode-Demo-${var.cluster_name}"
# }
#
# output "container_insights_addon_version" {
#   description = "Version of the CloudWatch observability addon"
#   value       = aws_eks_addon.cloudwatch_observability.addon_version
# }
