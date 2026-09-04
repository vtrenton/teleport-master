# ── Delegated DNS zone ─────────────────────────────────────────────────────────
# domain_name's DNS is hosted elsewhere, so rather than taking over the whole
# domain, only the Teleport cluster's own name (teleport_hostname.domain_name)
# is delegated to Route 53. This stack is destroyed/recreated often (proving
# out an ephemeral design), so the hosted zone is deliberately NOT a resource
# here - a Terraform-owned zone would get new name servers, and need re-
# delegating at the external DNS provider, on every destroy/apply cycle.
#
# Instead, create the zone once, out of band, before ever running `terraform
# apply` on this stack:
#   aws route53 create-hosted-zone --name teleport.trentonvanderwert.com \
#     --caller-reference "$(date +%s)"
# ...delegate it (NS record at the external DNS provider, once, using the
# name servers from that command's output)...and this data source just looks
# it up. It survives every `terraform destroy` on this project untouched.

locals {
  teleport_cluster_domain = "${var.teleport_hostname}.${var.domain_name}"
}

data "aws_route53_zone" "cluster" {
  name         = local.teleport_cluster_domain
  private_zone = false
}

# ── ExternalDNS Role (keeps the Teleport proxy's DNS record in sync with the
# AWS Load Balancer Controller's NLB, including across NLB recreation) ─────────

resource "aws_iam_role" "external_dns" {
  name = "${var.cluster_name}-external-dns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:external-dns"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "external_dns" {
  name = "${var.cluster_name}-external-dns-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ChangeDelegatedZoneOnly"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = data.aws_route53_zone.cluster.arn
      },
      {
        Sid    = "ReadAllZones"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  policy_arn = aws_iam_policy.external_dns.arn
  role       = aws_iam_role.external_dns.name
}
