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
./cluster-addons/install-lbc.sh
./cluster-addons/install-external-dns.sh
```
ExternalDNS watches the Teleport proxy's `Service` (annotated with
`external-dns.alpha.kubernetes.io/hostname` in the generated Helm values) and
keeps its DNS record pointed at the AWS Load Balancer Controller's NLB,
including if the NLB is destroyed and recreated.

## Enterprise license (skip if `teleport_enterprise = false`)
When `teleport_enterprise = true`, the generated values file sets
`enterprise: true` and `licenseSecretName: license`, but the license file
itself is never handled by Terraform or checked into this repo. Provision it
by hand, once, before `helm install` (the namespace must already exist -
`--create-namespace` on the Helm install below is too late for this):
```bash
kubectl create namespace teleport-cluster
kubectl create secret generic license \
  --from-file=license.pem=/path/to/license.pem \
  -n teleport-cluster
```

## Helm Install
```bash
helm install teleport-cluster teleport/teleport-cluster --namespace teleport-cluster --create-namespace --values teleport-cluster-values.yaml
```

## First admin user
The chart doesn't create any users. Bootstrap one via `tctl` inside the auth
pod once the deployment is up:
```bash
kubectl get pods -n teleport-cluster   # find the auth pod, e.g. teleport-cluster-auth-xxxxx
kubectl exec -it deploy/teleport-cluster-auth -n teleport-cluster -- \
  tctl users add trent --roles=editor,access --logins=root
```
This prints a one-time invite URL (default TTL 1h) - open it in a browser to
set a password and enroll MFA (required by default), then log in at
`https://teleport.trentonvanderwert.com` or via `tsh login --proxy=teleport.trentonvanderwert.com`.

