#!/usr/bin/env bash
# Installs cert-manager, applies the Route53 DNS-01 ClusterIssuer, restores
# a cached TLS cert if backup-tls-cert.sh saved one on a previous rebuild
# (checks the local terraform/out/ copy first, then falls back to AWS Secrets
# Manager for a fresh checkout / different machine), then applies the
# Teleport Certificate - out of band from the teleport-cluster Helm release,
# so `helm upgrade`/`helm uninstall` never touch it.
#
# cert-manager only orders from Let's Encrypt if the Secret is missing or
# invalid, so re-running this is always safe and never burns rate limit on
# its own.
#
# Requires jq and openssl locally.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
NAMESPACE="teleport-cluster"

echo "Fetching values from Terraform outputs..."
CLUSTER_NAME=$(tofu -chdir="$TERRAFORM_DIR" output -raw cluster_name)
ROLE_ARN=$(tofu -chdir="$TERRAFORM_DIR" output -raw cert_manager_role_arn)
K8S_SECRET_NAME=$(tofu -chdir="$TERRAFORM_DIR" output -raw teleport_tls_secret_name)
REGION="${AWS_DEFAULT_REGION:-$(aws configure get region)}"
LOCAL_BACKUP="$TERRAFORM_DIR/out/${CLUSTER_NAME}-teleport-tls.json"
SECRETS_MANAGER_NAME="${CLUSTER_NAME}-teleport-tls"

echo "Cluster:  $CLUSTER_NAME"
echo "Role ARN: $ROLE_ARN"
echo "Region:   $REGION"
echo ""

echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "Adding cert-manager Helm repo..."
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack

echo "Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --set serviceAccount.create=true \
  --set serviceAccount.name=cert-manager \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ROLE_ARN"

echo ""
echo "Waiting for cert-manager to be ready..."
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s

echo ""
echo "Applying ClusterIssuer (rendered by 'terraform apply' to $ROOT_DIR/cluster-issuer.yaml)..."
kubectl apply -f "$ROOT_DIR/cluster-issuer.yaml"

echo ""
echo "Ensuring namespace $NAMESPACE exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Checking for a cached TLS cert to restore..."
if kubectl get secret "$K8S_SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "$K8S_SECRET_NAME already exists in $NAMESPACE - leaving it alone."
elif [ -f "$LOCAL_BACKUP" ]; then
  echo "Found local backup at $LOCAL_BACKUP"
  PAYLOAD=$(cat "$LOCAL_BACKUP")
elif aws secretsmanager describe-secret --secret-id "$SECRETS_MANAGER_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "No local backup, but found one in Secrets Manager ($SECRETS_MANAGER_NAME) - fetching."
  PAYLOAD=$(aws secretsmanager get-secret-value --secret-id "$SECRETS_MANAGER_NAME" --region "$REGION" --query SecretString --output text)
else
  echo "No cached cert found anywhere - cert-manager will issue a fresh one."
fi

if [ -n "${PAYLOAD:-}" ]; then
  CRT_B64=$(echo "$PAYLOAD" | jq -r '."tls.crt"')
  KEY_B64=$(echo "$PAYLOAD" | jq -r '."tls.key"')

  CRT_PEM=$(mktemp)
  trap 'rm -f "$CRT_PEM"' EXIT
  echo "$CRT_B64" | base64 -d > "$CRT_PEM"

  if ! openssl x509 -in "$CRT_PEM" -checkend 86400 -noout >/dev/null 2>&1; then
    echo "Cached cert is expired or expires within 24h - skipping restore, cert-manager will issue a fresh one."
  else
    echo "Cached cert is valid ($(openssl x509 -in "$CRT_PEM" -noout -enddate)) - restoring."
    # The issuer annotations are what make cert-manager adopt this Secret -
    # without them it flags the Secret as "IncorrectIssuer" and immediately
    # orders a brand new cert, defeating the whole point of the restore.
    # Must match the issuerRef in teleport-certificate.yaml.
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $K8S_SECRET_NAME
  namespace: $NAMESPACE
  labels:
    controller.cert-manager.io/fao: "true"
  annotations:
    cert-manager.io/certificate-name: $K8S_SECRET_NAME
    cert-manager.io/issuer-name: letsencrypt-route53
    cert-manager.io/issuer-kind: ClusterIssuer
    cert-manager.io/issuer-group: cert-manager.io
type: kubernetes.io/tls
data:
  tls.crt: $CRT_B64
  tls.key: $KEY_B64
EOF
  fi
fi

echo ""
echo "Applying Teleport Certificate (rendered by 'terraform apply' to $ROOT_DIR/teleport-certificate.yaml)..."
kubectl apply -f "$ROOT_DIR/teleport-certificate.yaml"

echo ""
echo "Waiting for $K8S_SECRET_NAME to be Ready (a fresh DNS-01 issuance can take a few minutes)..."
kubectl wait --for=condition=Ready "certificate/$K8S_SECRET_NAME" -n "$NAMESPACE" --timeout=600s
kubectl get certificate "$K8S_SECRET_NAME" -n "$NAMESPACE"

echo ""
echo "Done. Back up the cert with ./cluster-addons/backup-tls-cert.sh (now, and before any terraform destroy)."
