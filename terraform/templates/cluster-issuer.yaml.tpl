# Rendered by Terraform (see cert_manager.tf), applied by
# cluster-addons/install-cert-manager.sh AFTER cert-manager's CRDs exist.
# Route 53 credentials come from cert-manager's pod via IRSA (ambient
# credentials) - ClusterIssuers use ambient credentials by default, so no
# accessKeyID/secretAccessKeySecretRef is needed here.
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-route53
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${acme_email}
    privateKeySecretRef:
      name: letsencrypt-route53-account-key
    solvers:
      - dns01:
          route53:
            region: ${region}
            hostedZoneID: ${hosted_zone_id}
        selector:
          dnsZones:
            - ${zone_domain}
