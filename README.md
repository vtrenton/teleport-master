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

## Kubeconfig
```bash
aws eks update-kubeconfig --region us-east-1 --name teleport-gateway
```
Substitute `region`/`cluster_name` if you've overridden their defaults in
`terraform.tfvars`. Everything below this point (`kubectl`, `helm`) needs
this run first.

## DNS delegation (one-time, out of band - do this before the first `terraform apply`)
This stack gets `terraform destroy`'d and rebuilt often, so the Route 53
hosted zone is deliberately **not** managed by this Terraform project - a
Terraform-owned zone gets brand new name servers every time it's recreated,
which would mean re-delegating at the external DNS provider on every
destroy/apply cycle. Instead, create the zone once, by hand, outside this
project's state:
```bash
aws route53 create-hosted-zone \
  --name aws.trentonvanderwert.com \
  --caller-reference "$(date +%s)"
```
Take the 4 name servers from that command's output (`DelegationSet.NameServers`)
and, at whatever DNS provider currently hosts `trentonvanderwert.com`, add an
NS record for `aws` pointing to them. This zone and its delegation now
live independently of this stack - `terraform apply`/`terraform destroy` here
only look it up (via a data source) and never create, modify, or delete it.

Note the Teleport hostname (`teleport.aws.trentonvanderwert.com`) lives *one
level under* this zone's apex, not at it - delegating the zone exactly at the
record name breaks ExternalDNS's TXT ownership tracking (its ownership
records are named by rewriting the record's own first label, which only
stays inside the zone if the record isn't the zone's apex).

If you ever change `domain_name` or `dns_subdomain`, repeat the above for
the new zone name first. (Migrating from an old zone: remove its NS
delegation record and, once the new setup is confirmed working, delete the
old hosted zone.)

## Load Balancer Controller + ExternalDNS
```bash
./cluster-addons/install-lbc.sh
./cluster-addons/install-external-dns.sh
```
ExternalDNS watches the Teleport proxy's `Service` (annotated with
`external-dns.alpha.kubernetes.io/hostname` in the generated Helm values) and
keeps its DNS record pointed at the AWS Load Balancer Controller's NLB,
including if the NLB is destroyed and recreated.

## cert-manager (Route 53 DNS-01)
```bash
./cluster-addons/install-cert-manager.sh
```
Requires `jq` and `openssl` locally. Run this *before* `helm install` -
the proxy pod mounts the `teleport-tls` Secret and won't start without it.

The TLS cert is managed by cert-manager **out of band from the
teleport-cluster Helm release**. Terraform renders the `Certificate` to
`teleport-certificate.yaml` (repo root, gitignored), this script applies it,
and the generated Helm values just point Teleport at the resulting Secret
via `tls.existingSecretName`. So `helm upgrade`/`helm uninstall` never
touch the cert, and cert-manager only orders a new cert from Let's Encrypt
when the Secret is missing, invalid, or within 30 days of expiry.

Why not the alternatives:
- Teleport's built-in ACME (`acme: true`) caches its cert on the proxy
  pod's local disk, so every pod restart (including every `helm upgrade`)
  requested a brand new cert and quickly hit Let's Encrypt's
  duplicate-certificate limit (5/week for the same set of hostnames).
- The chart's own cert-manager integration (`highAvailability.certManager`)
  makes the `Certificate` part of the Helm release, so chart/values changes
  on `helm upgrade` can change its spec (and trigger a reissue), and
  `helm uninstall` deletes it.

DNS-01 via Route 53 is required because the cert includes
`*.<clusterName>` (for app access), and Let's Encrypt only issues wildcards
via DNS-01.

The script installs cert-manager (IRSA-scoped to
`ChangeResourceRecordSets`/`ListResourceRecordSets` on just the delegated
zone), applies the `letsencrypt-route53` `ClusterIssuer`, restores a cached
cert if `backup-tls-cert.sh` saved one on a previous rebuild (checking
`terraform/out/` first, then Secrets Manager), and then applies the
`Certificate` and waits for it to be Ready. It's safe to re-run.

**Migrating a live cluster from `highAvailability.certManager`:** run
`helm upgrade` with the new values *first* (this removes the chart-owned
`Certificate`; the Secret itself stays), *then* run
`install-cert-manager.sh`. The script's `Certificate` adopts the existing
Secret, so nothing is reissued. Running them in the opposite order would let
`helm upgrade` delete the `Certificate` the script just applied.

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
`https://teleport.aws.trentonvanderwert.com` or via `tsh login --proxy=teleport.aws.trentonvanderwert.com`.

## Tearing down
First, back up the current TLS cert so the next rebuild doesn't have to
request a new one from Let's Encrypt. The cert isn't part of the Helm
release, so `helm uninstall` won't remove it. Destroying the cluster will.
```bash
./cluster-addons/backup-tls-cert.sh
```
This writes both a local copy (`terraform/out/<cluster_name>-teleport-tls.json`,
already gitignored the same way as the generated node SSH key) and an AWS
Secrets Manager copy that survives even if this machine doesn't. The next
`install-cert-manager.sh` run picks it back up automatically.

Then uninstall the Helm release *before* `terraform destroy`:
```bash
helm uninstall teleport-cluster --namespace teleport-cluster
```
The Teleport proxy `Service` is a `LoadBalancer` type, so the AWS Load
Balancer Controller manages an NLB plus two security groups for it (an
auto-created frontend SG and a cluster-wide shared backend SG,
`k8s-traffic-<cluster_name>-<hash>`) entirely outside Terraform's state - LBC
creates and deletes these itself via a finalizer on the Service, which only
gets to run if the Service is deleted while the cluster (and the LBC pod
running in it) is still up. If the cluster or VPC is torn down first, this
finalizer never runs and the NLB plus both security groups are orphaned -
find and delete them by hand in the AWS console/CLI (tagged
`elbv2.k8s.aws/cluster: <cluster_name>`) before subnets/VPC deletion will
succeed.

