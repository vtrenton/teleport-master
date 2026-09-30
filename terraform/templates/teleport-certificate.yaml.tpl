# Rendered by Terraform (see cert_manager.tf), applied by
# cluster-addons/install-cert-manager.sh - deliberately NOT part of the
# teleport-cluster Helm release, so `helm upgrade`/`helm uninstall` never
# touch it. Teleport just mounts the resulting Secret via
# tls.existingSecretName.
#
# cert-manager only orders a new cert from Let's Encrypt when the Secret is
# missing, doesn't match this spec, or is within renewBefore of expiry. Any
# edit to dnsNames/issuerRef here WILL trigger a new order - keep it stable.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${secret_name}
  namespace: ${namespace}
spec:
  secretName: ${secret_name}
  dnsNames:
    - ${cluster_domain}
    - "*.${cluster_domain}"
  issuerRef:
    name: letsencrypt-route53
    kind: ClusterIssuer
    group: cert-manager.io
