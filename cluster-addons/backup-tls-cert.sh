#!/usr/bin/env bash
# Backs up the cert-manager-issued "teleport-tls" Secret so the next rebuild
# doesn't have to request a new certificate from Let's Encrypt.
#
# The Certificate/Secret live outside the teleport-cluster Helm release, so
# `helm upgrade`/`helm uninstall` don't affect them - only destroying the
# cluster does. Run this before `terraform destroy` (and any time after a
# renewal, to keep the cache current).
#
# Writes two copies: terraform/out/<cluster_name>-teleport-tls.json (fast
# path for a rebuild on this same machine, already gitignored the same way
# as the generated node SSH key) and an AWS Secrets Manager secret of the
# same name (durable if this machine goes away). install-cert-manager.sh
# checks the local file first, then falls back to Secrets Manager.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
NAMESPACE="teleport-cluster"

CLUSTER_NAME=$(tofu -chdir="$TERRAFORM_DIR" output -raw cluster_name)
K8S_SECRET_NAME=$(tofu -chdir="$TERRAFORM_DIR" output -raw teleport_tls_secret_name)
SECRETS_MANAGER_NAME="${CLUSTER_NAME}-teleport-tls"
LOCAL_BACKUP="$TERRAFORM_DIR/out/${CLUSTER_NAME}-teleport-tls.json"
REGION="${AWS_DEFAULT_REGION:-$(aws configure get region)}"

if ! kubectl get secret "$K8S_SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "No $K8S_SECRET_NAME secret found in namespace $NAMESPACE - nothing to back up."
  exit 0
fi

echo "Reading $K8S_SECRET_NAME from namespace $NAMESPACE..."
PAYLOAD=$(kubectl get secret "$K8S_SECRET_NAME" -n "$NAMESPACE" -o json |
  jq '{"tls.crt": .data["tls.crt"], "tls.key": .data["tls.key"]}')

mkdir -p "$(dirname "$LOCAL_BACKUP")"
echo "$PAYLOAD" > "$LOCAL_BACKUP"
echo "Wrote local backup to $LOCAL_BACKUP"

echo "Saving to Secrets Manager secret $SECRETS_MANAGER_NAME (region $REGION)..."
if aws secretsmanager describe-secret --secret-id "$SECRETS_MANAGER_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value \
    --secret-id "$SECRETS_MANAGER_NAME" \
    --secret-string "$PAYLOAD" \
    --region "$REGION" >/dev/null
else
  aws secretsmanager create-secret \
    --name "$SECRETS_MANAGER_NAME" \
    --description "Cached Teleport proxy TLS cert (tls.crt/tls.key, base64) - survives terraform destroy/rebuild cycles of $CLUSTER_NAME" \
    --secret-string "$PAYLOAD" \
    --region "$REGION" >/dev/null
fi

echo "Done. Run this again before every 'terraform destroy' to keep the cache current."
