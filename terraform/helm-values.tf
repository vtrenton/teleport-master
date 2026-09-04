# Renders the Helm values file consumed by the (separate, manual) `helm install`
# step for the teleport-cluster chart - see README.md. Terraform only generates
# the file; it does not invoke Helm itself.

resource "local_file" "teleport_cluster_values" {
  filename = "${path.module}/../teleport-cluster-values.yaml"

  content = templatefile("${path.module}/templates/teleport-cluster-values.yaml.tpl", {
    region                      = var.region
    cluster_domain              = local.teleport_cluster_domain
    acme_email                  = var.acme_email
    dynamodb_backend_table_name = var.dynamodb_backend_table_name
    dynamodb_events_table_name  = var.dynamodb_events_table_name
    s3_bucket_name              = var.s3_bucket_name
    teleport_storage_role_arn   = aws_iam_role.teleport_storage.arn
  })
}
