#!/bin/bash
# Deploy CloudWatch Dashboard for EKS Auto Mode Demo
# Usage: ./deploy-dashboard.sh [cluster-name] [region]

set -e

CLUSTER_NAME="${1:-eks-auto-demo}"
REGION="${2:-us-west-2}"
DASHBOARD_NAME="EKS-AutoMode-Demo-${CLUSTER_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== CloudWatch Dashboard Deployment ==="
echo "Cluster:   ${CLUSTER_NAME}"
echo "Region:    ${REGION}"
echo "Dashboard: ${DASHBOARD_NAME}"
echo ""

# Step 1: Enable Container Insights addon (if not already installed)
echo ">> Checking CloudWatch Observability addon..."
ADDON_STATUS=$(aws eks describe-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name amazon-cloudwatch-observability \
  --region "${REGION}" \
  --query 'addon.status' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${ADDON_STATUS}" = "NOT_FOUND" ]; then
  echo ">> Installing amazon-cloudwatch-observability addon..."
  aws eks create-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name amazon-cloudwatch-observability \
    --region "${REGION}"
  
  echo ">> Waiting for addon to become ACTIVE (this may take 2-3 minutes)..."
  aws eks wait addon-active \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name amazon-cloudwatch-observability \
    --region "${REGION}" 2>/dev/null || \
  # Fallback polling if 'wait' subcommand not available
  for i in $(seq 1 30); do
    STATUS=$(aws eks describe-addon \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name amazon-cloudwatch-observability \
      --region "${REGION}" \
      --query 'addon.status' --output text 2>/dev/null || echo "CREATING")
    echo "   Addon status: ${STATUS}"
    if [ "${STATUS}" = "ACTIVE" ]; then break; fi
    sleep 10
  done
  echo ">> Addon installed."
else
  echo ">> Addon already present (status: ${ADDON_STATUS})"
fi

# Step 2: Generate dashboard body with correct cluster name and region
echo ""
echo ">> Generating dashboard JSON..."
DASHBOARD_BODY=$(cat "${SCRIPT_DIR}/dashboard.json" \
  | sed "s/eks-auto-demo/${CLUSTER_NAME}/g" \
  | sed "s/us-west-2/${REGION}/g")

# Step 3: Deploy the dashboard
echo ">> Deploying CloudWatch dashboard: ${DASHBOARD_NAME}..."
aws cloudwatch put-dashboard \
  --dashboard-name "${DASHBOARD_NAME}" \
  --dashboard-body "${DASHBOARD_BODY}" \
  --region "${REGION}"

echo ""
echo "=== Dashboard deployed successfully ==="
echo ""
echo "Open in browser:"
echo "  https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards/dashboard/${DASHBOARD_NAME}"
echo ""
echo "Note: Metrics will start appearing ~2 minutes after Container Insights"
echo "      addon is active and workloads are running."
