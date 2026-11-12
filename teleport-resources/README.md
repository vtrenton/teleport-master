# teleport-resources

Teleport resources as code for the labs (the `labconf` repo): roles, join
tokens, bots, workload identities, SAML apps and Managed Updates. Argo CD
syncs this directory into the `teleport-cluster` namespace (Application and
AppProject `teleport-resources`, `argo/addons/templates/teleport-resources.yaml`),
where the chart's operator turns them into Teleport resources. Paths in the
comments of these files (`infralab/…`, `pilab/…`, `binddns/…`, `hv1/…`) are in
the labconf repo.

- **Pruning is on**: deleting a file here deletes the resource in Teleport.
- The AppProject allows only these kinds, in that namespace, nothing
  cluster-scoped: `TeleportRoleV8`, `TeleportProvisionToken`, `TeleportBotV1`,
  `TeleportWorkloadIdentityV1`, `TeleportSAMLIdPServiceProviderV1`,
  `TeleportAutoupdateConfigV1`, `TeleportAutoupdateVersionV1`. A new kind
  needs adding there first.
- The operator only manages what it created (`teleport.dev/origin:
  kubernetes`), so resources made with `tctl` are left alone. A rebuilt
  cluster's operator takes all of these over again.
- Nothing here is a secret: every join is delegated (Kubernetes JWKS for
  in-cluster agents, TPM for nodes), so token contents (public signing keys,
  TPM EK hashes) are safe in a public repo.
- Users stay out of git. Grant the lab roles with
  `tctl users update <user> --set-roles editor,access,lab-admin,labns-admin,hv1-admin`.

| File | Resources |
|---|---|
| `tokens-nodes.yaml` | `infralab-nodes`, `pilab-nodes`, `labns-node`, `hv1-node` (`Node, App`): TPM joins, one rule per node EK |
| `tokens-kube-agents.yaml` | `infralab-kube-agent` (`Kube, App, Discovery`), `pilab-kube-agent` (`Kube, App`): Kubernetes JWKS |
| `roles.yaml` | `lab-admin`: SSH (`sysadmin`/`admin`), `system:masters` and the apps on infralab/pilab, driving agent update rollouts. `labns-admin`: SSH as `root` on `labns` only. `hv1-admin`: SSH as `root` on `hv1` and its Proxmox UI (app `proxmox-hv1`) |
| `argocd-access.yaml` | Bot `labconf-argocd` + role `labconf-argocd-deployer` (`system:masters` on `lab: pilab`) + its token: infralab's Argo CD reaching pilab |
| `argocd-sso.yaml` | SAML service provider `argocd` (Teleport as infralab Argo CD's IdP) |
| `cert-manager-identity.yaml` | Workload identity `infralab-cert-manager` + issuer role + bot `labconf-cert-manager` + token: keyless Route 53 |
| `alertmanager-identity.yaml` | Workload identity `infralab-alertmanager` + issuer role + bot `labconf-alertmanager` + token: keyless SNS |
| `autoupdate.yaml` | Managed Updates: groups `infralab`, then `pilab`, `labns`, `hv1`, each 24 h after the previous; target version (agents never newer than the cluster) |

| Event | Do |
|---|---|
| **infralab or pilab rebuilt** | Its service-account signing keys are new: update its JWKS (`kubectl get --raw /openid/v1/jwks`) in `tokens-kube-agents.yaml` and, for infralab, `cert-manager-identity.yaml`, `alertmanager-identity.yaml`, `argocd-access.yaml`. |
| **A node's TPM cleared or board replaced** | `teleport tpm identify` on it; update its rule in `tokens-nodes.yaml`. |
| **Teleport upgraded** | `autoupdate.yaml`'s target version, after the cluster. |

**Risk:** the operator can write Teleport roles, which means it can grant any
access. Anyone who can merge to this repo's deployed branch, or who controls
this EKS cluster (and with it its Argo CD), can therefore become Teleport
admin. The labs' clusters and the labconf repo can't. Mitigations: the
AppProject's kind limits, branch protection, and a break-glass admin outside
git.
