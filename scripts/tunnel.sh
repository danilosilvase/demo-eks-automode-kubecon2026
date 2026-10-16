#!/bin/bash
# =============================================================================
# Reach the private EKS API endpoint from your laptop, with nothing exposed publicly.
# Opens an SSM port-forward: localhost:8443 -> SSM access host -> private API endpoint:443.
# Keep it running in its own terminal while you use kubectl.
#
# Needs: AWS CLI v2, the Session Manager plugin, and the Terraform outputs in ./terraform.
# First time only, point kubectl at the tunnel (the command is also in `terraform output configure_kubectl`):
#   aws eks update-kubeconfig --name <cluster> --region <region>
#   kubectl config set-cluster <cluster-arn> --server=https://127.0.0.1:8443 --tls-server-name=<endpoint-host>
# =============================================================================
set -e
cd "$(dirname "$0")/../terraform"
command -v session-manager-plugin >/dev/null || {
  echo "ERROR: Session Manager plugin not found: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"; exit 1; }
REGION=$(terraform output -raw region 2>/dev/null || echo "${AWS_REGION:-us-west-2}")
IID=$(terraform output -raw ssm_access_instance_id)
HOST=$(terraform output -raw cluster_endpoint | sed 's#https://##')
LOCAL_PORT="${LOCAL_PORT:-8443}"
echo "Forwarding localhost:${LOCAL_PORT} -> ${HOST}:443 via ${IID} (Ctrl+C to stop)"
exec aws ssm start-session --region "$REGION" --target "$IID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=${HOST},portNumber=443,localPortNumber=${LOCAL_PORT}"
