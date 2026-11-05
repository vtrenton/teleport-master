# Renders the Helm values file consumed by the (separate, manual) `helm install`
# step for the teleport-cluster chart - see README.md. Terraform only generates
# the file; it does not invoke Helm itself.

data "aws_nat_gateways" "vpc" {
  vpc_id = var.vpc_id

  # Deleted NAT gateways stay listed for a while after removal.
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_nat_gateway" "vpc" {
  for_each = toset(data.aws_nat_gateways.vpc.ids)
  id       = each.value
}

locals {
  # compact() drops private NAT gateways, which have no public IP.
  nat_gateway_public_ips = sort(compact([for nat in data.aws_nat_gateway.vpc : nat.public_ip]))
}

resource "local_file" "teleport_cluster_values" {
  filename = "${path.module}/../teleport-cluster-values.yaml"

  content = templatefile("${path.module}/templates/teleport-cluster-values.yaml.tpl", {
    region                      = var.region
    cluster_domain              = local.teleport_cluster_domain
    tls_secret_name             = local.teleport_tls_secret_name
    dynamodb_backend_table_name = var.dynamodb_backend_table_name
    dynamodb_events_table_name  = var.dynamodb_events_table_name
    s3_bucket_name              = var.s3_bucket_name
    teleport_storage_role_arn   = aws_iam_role.teleport_storage.arn
    enterprise                  = var.teleport_enterprise
    home_ip                     = var.home_ip
    nat_gateway_public_ips      = local.nat_gateway_public_ips
  })
}
