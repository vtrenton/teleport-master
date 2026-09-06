# ── Delegated DNS zone ─────────────────────────────────────────────────────────
# domain_name's DNS is hosted elsewhere, so rather than taking over the whole
# domain, only a subdomain (dns_subdomain.domain_name, e.g.
# "aws.trentonvanderwert.com") is delegated to Route 53 - with the Teleport
# hostname living ONE LEVEL UNDER that zone's apex, not AT it. This isn't just
# style: ExternalDNS's TXT ownership records are named by rewriting the first
# label of the managed name (e.g. "teleport" -> "cname-teleport") while
# leaving everything after the first dot untouched, so if the zone's apex IS
# the managed record itself, the computed ownership name is a SIBLING of the
# zone root, not a child of it, and falls outside the zone entirely - Route 53
# refuses it (verified: a direct query returns REFUSED, not NODATA). No
# --txt-prefix/--txt-suffix combination fixes this; the zone genuinely needs
# a free label for the record to live under.
#
# This stack is also destroyed/recreated often (proving out an ephemeral
# design), so the hosted zone is deliberately NOT a Terraform resource here -
# a Terraform-owned zone would get new name servers, and need re-delegating
# at the external DNS provider, on every destroy/apply cycle.
#
# Instead, create the zone once, out of band, before ever running `terraform
# apply` on this stack:
#   aws route53 create-hosted-zone --name aws.trentonvanderwert.com \
#     --caller-reference "$(date +%s)"
# ...delegate it (NS record at the external DNS provider, once, using the
# name servers from that command's output)...and this data source just looks
# it up. It survives every `terraform destroy` on this project untouched.

locals {
  zone_domain             = "${var.dns_subdomain}.${var.domain_name}"
  teleport_cluster_domain = "${var.teleport_hostname}.${local.zone_domain}"
}

data "aws_route53_zone" "cluster" {
  name         = local.zone_domain
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
