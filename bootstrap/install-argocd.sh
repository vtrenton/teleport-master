#!/usr/bin/env bash
# Installs Argo CD, then the "addons" root Application: Argo CD deploys the
# AWS Load Balancer Controller, ExternalDNS and cert-manager from argo/addons
# in this repo (on GitHub: push first). Values specific to this AWS account
# (role ARNs, VPC ID, tags) come from the Terraform outputs, the same way the
# old install scripts passed them with --set. Safe to re-run, e.g. after a
# `tofu apply` that changes one of them.
#
# Requires jq locally.
set -euo pipefail

ARGOCD_CHART_VERSION="10.17.2" # argo/argo-cd (Argo CD v3.6.1)
REPO_URL="https://github.com/vtrenton/teleport-master"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
# Branch Argo CD follows (default: the one checked out here)
REVISION="${ARGO_REVISION:-$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)}"

if [ "$(git -C "$ROOT_DIR" rev-parse HEAD)" != "$(git -C "$ROOT_DIR" rev-parse "origin/$REVISION" 2>/dev/null)" ]; then
  echo "Warning: HEAD is not what origin/$REVISION has; Argo CD deploys origin/$REVISION." >&2
fi

echo "Fetching values from Terraform outputs..."
tf() { tofu -chdir="$TERRAFORM_DIR" output "$@"; }
CLUSTER_NAME=$(tf -raw cluster_name)
REGION="${AWS_DEFAULT_REGION:-$(aws configure get region)}"
VALUES=$(jq -n \
  --arg clusterName "$CLUSTER_NAME" \
  --arg region "$REGION" \
  --arg vpcId "$(tf -raw vpc_id)" \
  --argjson resourceTags "$(tf -json resource_tags)" \
  --arg zoneDomain "$(tf -raw route53_zone_domain)" \
  --arg lbc "$(tf -raw lbc_role_arn)" \
  --arg externalDns "$(tf -raw external_dns_role_arn)" \
  --arg certManager "$(tf -raw cert_manager_role_arn)" \
  --arg revision "$REVISION" \
  '{clusterName: $clusterName, region: $region, vpcId: $vpcId, resourceTags: $resourceTags,
    zoneDomain: $zoneDomain, roles: {lbc: $lbc, externalDns: $externalDns, certManager: $certManager},
    revision: $revision}')

echo "Cluster:  $CLUSTER_NAME"
echo "Region:   $REGION"
echo "Revision: $REVISION"
echo ""

echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "Installing Argo CD..."
helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace \
  --wait --timeout 10m

# No resources-finalizer: deleting the Application never deletes the add-ons.
echo "Applying the addons root Application..."
jq -n --arg repo "$REPO_URL" --arg rev "$REVISION" --argjson values "$VALUES" '{
  apiVersion: "argoproj.io/v1alpha1", kind: "Application",
  metadata: {name: "addons", namespace: "argocd"},
  spec: {
    project: "default",
    source: {repoURL: $repo, targetRevision: $rev, path: "argo/addons", helm: {valuesObject: $values}},
    destination: {server: "https://kubernetes.default.svc", namespace: "argocd"},
    syncPolicy: {automated: {prune: true, selfHeal: true}}
  }}' | kubectl apply -f -

echo ""
echo "Done. Watch the add-ons sync with: kubectl -n argocd get applications"
echo "Argo CD UI: kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "  user admin, password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
