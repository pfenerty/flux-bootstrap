# Cluster template

Copy this directory to `clusters/<project_name>` and commit it before the
first `terraform apply`. Nothing here is specific to a cluster, which is the
point: what differs between clusters is Terraform's to supply, through the
secrets `modules/bootstrap` writes into `flux-system` and `kube-system`.

| File | Layer |
|---|---|
| `infrastructure.yaml` | Cloud controller, cert-manager, Cilium, CSR approver, metrics-server, EBS CSI, Karpenter |
| `observability.yaml` | Prometheus, Grafana, Loki, Alloy, Tetragon |
| `policy.yaml` | Kyverno and its policies, default-deny network policy |

Delete a file to leave that layer out. See [`../README.md`](../README.md).
