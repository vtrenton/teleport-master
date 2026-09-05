#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"

echo "Fetching values from Terraform outputs..."
CLUSTER_NAME=$(tofu -chdir="$TERRAFORM_DIR" output -raw cluster_name)
ROLE_ARN=$(tofu -chdir="$TERRAFORM_DIR" output -raw external_dns_role_arn)
ZONE_DOMAIN=$(tofu -chdir="$TERRAFORM_DIR" output -raw teleport_cluster_domain)
REGION="${AWS_DEFAULT_REGION:-$(aws configure get region)}"

echo "Cluster:      $CLUSTER_NAME"
echo "Role ARN:     $ROLE_ARN"
echo "Zone domain:  $ZONE_DOMAIN"
echo "Region:       $REGION"
echo ""

echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "Adding external-dns Helm repo..."
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns

echo "Installing ExternalDNS..."
helm upgrade --install external-dns external-dns/external-dns \
  --namespace kube-system \
  --set provider.name=aws \
  --set "domainFilters[0]=$ZONE_DOMAIN" \
  --set policy=upsert-only \
  --set txtOwnerId="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-dns \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ROLE_ARN" \
  --set "env[0].name=AWS_DEFAULT_REGION" \
  --set "env[0].value=$REGION"

echo ""
echo "Waiting for external-dns to be ready..."
kubectl rollout status deployment/external-dns -n kube-system --timeout=120s

echo ""
echo "Done. ExternalDNS is running and will manage records in $ZONE_DOMAIN."
kubectl get pods -n kube-system -l app.kubernetes.io/name=external-dns
