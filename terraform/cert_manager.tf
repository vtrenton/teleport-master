# cert-manager (Route 53 DNS-01) - replaces Teleport's built-in ACME client.
#
# The built-in client (the old `acme: true` / `acmeEmail` values) caches its
# certificate locally on the single Proxy pod, not in the shared DynamoDB
# backend - every pod replacement (and definitely every `terraform destroy`
# rebuild of this stack) loses that cache and requests a brand new
# certificate from Let's Encrypt, which is what was hitting the "duplicate
# certificate" rate limit (5/week per exact hostname) on repeated
# destroy/rebuild cycles.
#
# cert-manager instead stores the certificate in a Kubernetes Secret
# ("teleport-tls" in the "teleport-cluster" namespace) and only re-issues
# when that secret is missing, invalid, or actually expiring.
#
# The Certificate is deliberately NOT created by the teleport-cluster chart
# (highAvailability.certManager) - a chart-owned Certificate is at the mercy
# of every `helm upgrade`/`helm uninstall`. Instead it's rendered here and
# applied out of band by cluster-addons/install-cert-manager.sh, and the
# chart just mounts the Secret via tls.existingSecretName. The only thing
# that loses it is a full cluster rebuild - see cluster-addons/backup-tls-cert.sh
# (run before `terraform destroy`) and install-cert-manager.sh's restore step.
#
# It includes "*.<clusterName>" (for Teleport app access subdomains) - Let's
# Encrypt only issues wildcards via DNS-01, hence Route 53 DNS-01.

locals {
  teleport_namespace       = "teleport-cluster"
  teleport_tls_secret_name = "teleport-tls"
}

resource "aws_iam_role" "cert_manager" {
  name = "${var.cluster_name}-cert-manager-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:cert-manager:cert-manager"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "cert_manager" {
  name = "${var.cluster_name}-cert-manager-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ChangeDelegatedZoneOnly"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
        Resource = data.aws_route53_zone.cluster.arn
      },
      {
        Sid      = "PollDnsChallengePropagation"
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  policy_arn = aws_iam_policy.cert_manager.arn
  role       = aws_iam_role.cert_manager.name
}

# hostedZoneID is pinned explicitly in the rendered ClusterIssuer so
# cert-manager never needs route53:ListHostedZonesByName (which can't be
# scoped to one zone).
resource "local_file" "cluster_issuer" {
  filename = "${path.module}/../cluster-issuer.yaml"

  content = templatefile("${path.module}/templates/cluster-issuer.yaml.tpl", {
    acme_email     = var.acme_email
    region         = var.region
    hosted_zone_id = data.aws_route53_zone.cluster.zone_id
    zone_domain    = local.zone_domain
  })
}

resource "local_file" "teleport_certificate" {
  filename = "${path.module}/../teleport-certificate.yaml"

  content = templatefile("${path.module}/templates/teleport-certificate.yaml.tpl", {
    secret_name    = local.teleport_tls_secret_name
    namespace      = local.teleport_namespace
    cluster_domain = local.teleport_cluster_domain
  })
}
