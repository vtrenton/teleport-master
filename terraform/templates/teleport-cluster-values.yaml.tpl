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
