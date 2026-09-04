# Deploying

## Terraform Base
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

This also renders `teleport-cluster-values.yaml` (repo root) from
`terraform/templates/teleport-cluster-values.yaml.tpl`, filling in the region,
DynamoDB/S3 backend names, and IRSA role ARN for `chartMode: aws`. The file is
generated, not tracked in git - re-run `terraform apply` after changing the
relevant variables to regenerate it.

## DNS delegation (one-time, out of band - do this before the first `terraform apply`)
This stack gets `terraform destroy`'d and rebuilt often, so the Route 53
hosted zone is deliberately **not** managed by this Terraform project - a
Terraform-owned zone gets brand new name servers every time it's recreated,
which would mean re-delegating at the external DNS provider on every
destroy/apply cycle. Instead, create the zone once, by hand, outside this
project's state:
```bash
aws route53 create-hosted-zone \
  --name teleport.trentonvanderwert.com \
  --caller-reference "$(date +%s)"
```
Take the 4 name servers from that command's output (`DelegationSet.NameServers`)
and, at whatever DNS provider currently hosts `trentonvanderwert.com`, add an
NS record for `teleport` pointing to them. This zone and its delegation now
live independently of this stack - `terraform apply`/`terraform destroy` here
only look it up (via a data source) and never create, modify, or delete it.

If you ever change `domain_name` or `teleport_hostname`, repeat the above for
the new name first.

## Load Balancer Controller + ExternalDNS
```bash
./eks-lb-install/install-lbc.sh
./eks-lb-install/install-external-dns.sh
```
ExternalDNS watches the Teleport proxy's `Service` (annotated with
`external-dns.alpha.kubernetes.io/hostname` in the generated Helm values) and
keeps its DNS record pointed at the AWS Load Balancer Controller's NLB,
including if the NLB is destroyed and recreated.

## Helm Install
```bash
helm install teleport-cluster teleport/teleport-cluster --namespace teleport-cluster --create-namespace --values teleport-cluster-values.yaml
```

