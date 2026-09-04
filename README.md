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

## Helm Install
```bash
helm install teleport-cluster teleport/teleport-cluster --namespace teleport-cluster --create-namespace --values teleport-cluster-values.yaml
```

