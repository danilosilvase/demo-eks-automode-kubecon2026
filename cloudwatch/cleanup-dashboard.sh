#!/bin/bash
# Remove CloudWatch Dashboard for EKS Auto Mode Demo
# Usage: ./cleanup-dashboard.sh [cluster-name] [region]

set -e

CLUSTER_NAME="${1:-eks-auto-demo}"
REGION="${2:-eu-central-1}"
DASHBOARD_NAME="EKS-AutoMode-Demo-${CLUSTER_NAME}"

echo "=== CloudWatch Dashboard Cleanup ==="
echo "Deleting dashboard: ${DASHBOARD_NAME}..."

aws cloudwatch delete-dashboards \
  --dashboard-names "${DASHBOARD_NAME}" \
  --region "${REGION}" 2>/dev/null && \
  echo "Dashboard deleted." || \
  echo "Dashboard not found (already deleted or never created)."

echo ""
echo "Note: The amazon-cloudwatch-observability addon is left in place."
echo "      Remove it manually if desired:"
echo "      aws eks delete-addon --cluster-name ${CLUSTER_NAME} --addon-name amazon-cloudwatch-observability --region ${REGION}"
