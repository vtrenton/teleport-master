output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = var.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used for the cluster, node group, and Teleport proxy NLB"
  value       = var.subnet_ids
}

output "lbc_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller"
  value       = aws_iam_role.lbc.arn
}

output "teleport_storage_role_arn" {
  description = "IAM role ARN for S3/DynamoDB access - set as annotations.serviceAccount[\"eks.amazonaws.com/role-arn\"] in the teleport-cluster Helm values, with serviceAccount.name set to \"teleportstorage\" (namespace \"teleport\") - covers both the auth and auto-suffixed \"-proxy\" ServiceAccounts the chart creates"
  value       = aws_iam_role.teleport_storage.arn
}

output "route53_zone_name_servers" {
  description = "Name servers of the (manually created, out-of-band) Route 53 zone this stack looks up - informational only, for verifying NS delegation at the external DNS provider matches; this stack never creates or destroys the zone"
  value       = data.aws_route53_zone.cluster.name_servers
}

output "external_dns_role_arn" {
  description = "IAM role ARN for ExternalDNS (IRSA) - installed via cluster-addons/install-external-dns.sh, keeps the Teleport proxy's DNS record in sync with the NLB"
  value       = aws_iam_role.external_dns.arn
}

output "teleport_cluster_domain" {
  description = "Full public DNS name for the Teleport proxy - set as the Helm chart's clusterName and its external-dns.alpha.kubernetes.io/hostname service annotation (both already done in the generated teleport-cluster-values.yaml)"
  value       = local.teleport_cluster_domain
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl after apply"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}
