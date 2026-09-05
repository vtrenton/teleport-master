#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"

echo "Fetching values from Terraform outputs..."
CLUSTER_NAME=$(terraform -chdir="$TERRAFORM_DIR" output -raw cluster_name)
LBC_ROLE_ARN=$(terraform -chdir="$TERRAFORM_DIR" output -raw lbc_role_arn)
VPC_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw vpc_id)
REGION="${AWS_DEFAULT_REGION:-$(aws configure get region)}"

echo "Cluster:  $CLUSTER_NAME"
echo "Role ARN: $LBC_ROLE_ARN"
echo "VPC ID:   $VPC_ID"
echo "Region:   $REGION"
echo ""

echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "Adding EKS Helm repo..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

echo "Installing AWS Load Balancer Controller..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$LBC_ROLE_ARN" \
  --set vpcId="$VPC_ID" \
  --set region="$REGION"

echo ""
echo "Waiting for controller pods to be ready..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s

echo ""
echo "Done. AWS Load Balancer Controller is running."
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
