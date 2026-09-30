chartMode: aws

clusterName: ${cluster_domain}
proxyListenerMode: multiplex

aws:
  region: ${region}
  backendTable: ${dynamodb_backend_table_name}
  auditLogTable: ${dynamodb_events_table_name}
  sessionRecordingBucket: ${s3_bucket_name}
  dynamoAutoScaling: false

# TLS cert is issued by cert-manager OUT OF BAND from this Helm release
# (Certificate applied by cluster-addons/install-cert-manager.sh), so
# `helm upgrade`/`helm uninstall` can never delete or re-trigger it. Don't
# switch this to highAvailability.certManager - that puts the Certificate
# back inside the release.
tls:
  existingSecretName: ${tls_secret_name}

# Enterprise license - the "license" Secret itself is provisioned manually
# (kubectl create secret generic license --from-file=license.pem=/path/to/license.pem
# -n teleport-cluster) BEFORE `helm install`; never checked into this repo or
# handled by Terraform.
enterprise: ${enterprise}
licenseSecretName: license

# Enable kubernetes operator for kubernetes native pattern
operator:
  enabled: true

podSecurityPolicy:
  enabled: false

serviceAccount:
  name: teleportstorage

# serviceAccount role-arn annotation stays at top level deliberately - both
# the auth ("teleportstorage") and proxy ("teleportstorage-proxy")
# ServiceAccounts need it, and both inherit top-level `annotations` via the
# chart's per-component value merge.
annotations:
  serviceAccount:
    eks.amazonaws.com/role-arn: "${teleport_storage_role_arn}"

# LBC/ExternalDNS Service annotations, scoped to the proxy's Service ONLY
# (not top-level `annotations.service`, which the chart also merges onto the
# internal auth ClusterIP Service - NLB/target-type annotations on a
# ClusterIP service can confuse the AWS Load Balancer Controller's finalizer
# handling and get that Service stuck terminating on `helm uninstall`).
proxy:
  # An existing TLS secret satisfies the "proxy pods need a certificate to
  # be replicated" requirement, which would otherwise default the Proxy to 2
  # replicas - pin it back to 1 to keep this a single-replica lab deployment.
  highAvailability:
    replicaCount: 1
  annotations:
    service:
      service.beta.kubernetes.io/aws-load-balancer-type: "external"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
      external-dns.alpha.kubernetes.io/hostname: "${cluster_domain}"
