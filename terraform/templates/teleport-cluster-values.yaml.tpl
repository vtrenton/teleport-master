chartMode: aws

clusterName: ${cluster_domain}
proxyListenerMode: multiplex

aws:
  region: ${region}
  backendTable: ${dynamodb_backend_table_name}
  auditLogTable: ${dynamodb_events_table_name}
  sessionRecordingBucket: ${s3_bucket_name}
  dynamoAutoScaling: false

acme: true
acmeEmail: ${acme_email}

# Enterprise license - the "license" Secret itself is provisioned manually
# (kubectl create secret generic license --from-file=license.pem=/path/to/license.pem
# -n teleport-cluster) BEFORE `helm install`; never checked into this repo or
# handled by Terraform.
enterprise: ${enterprise}
licenseSecretName: license

podSecurityPolicy:
  enabled: false

serviceAccount:
  name: teleportstorage

annotations:
  serviceAccount:
    eks.amazonaws.com/role-arn: "${teleport_storage_role_arn}"
  service:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    external-dns.alpha.kubernetes.io/hostname: "${cluster_domain}"
