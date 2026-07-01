kubectl -n teleport-cluster exec -i deployment/teleport-cluster-auth -- tctl create -f < member.yaml
kubectl -n teleport-cluster exec -ti deployment/teleport-cluster-auth -- tctl users add trent --roles=member,access,editor
