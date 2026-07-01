# Deploying

## Terraform Base
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

## K8s deployments
```bash
cd k8s/
kubectl apply -f teleport-ns.yaml
kubectl apply -f storage.yaml
```

## Helm Install
```bash
helm install teleport-cluster teleport/teleport-cluster --namespace teleport-cluster --values teleport-cluster-values.yaml
```

