# Flux Bootstrap

The GitOps half of a Talos Linux cluster on AWS. Terraform builds the cluster
and hands it over; everything that runs *in* the cluster is here.

Written against
[pfenerty/talos-aws-terraform](https://github.com/pfenerty/talos-aws-terraform),
which bootstraps Flux against this repository at the end of a single
`terraform apply` and publishes the secrets these manifests read.

## The handover

Terraform gets the cluster to the point where Flux can run, and no further:

```
talos bootstrap → bootstrap Cilium → cluster health → flux bootstrap → this repository
```

The bootstrap Cilium is deliberately minimal - enough for nodes to reach
Ready, without encryption or Hubble - and Terraform stops reconciling it. The
Cilium `HelmRelease` here adopts that same release and upgrades it in place.
Cilium is the one component this repository takes over rather than installs.

What it inherits, and what it must not break:

| Secret | Namespace | Read by |
|---|---|---|
| `cilium-config` | `flux-system` | Cilium, for the strict-mode encryption CIDR. It has to match the pod CIDR the machine configs were generated with. |
| `karpenter-config` | `flux-system` | Karpenter's `HelmRelease`, and the `EC2NodeClass` and `NodePool` chart |
| `karpenter-aws-credentials` | `kube-system` | The Karpenter controller's environment |
| `aws-secret` | `kube-system` | The EBS CSI driver |
| `hubble-trust-anchor` | `kube-system` | cert-manager, as the CA the Hubble `Issuer` signs from |

`aws-loadbalancer-config` is also written by Terraform and read by nothing
here.

## Layout

```
clusters/<project_name>/    what one cluster runs, as Flux Kustomizations
platform/                   what those Kustomizations point at
charts/                     charts that only exist for this repository
```

`clusters/` holds no manifests and `platform/` holds no cluster-specific
values. Everything that differs between clusters arrives in a secret from
Terraform, which is why a second cluster is three copied files and not a
second copy of the platform.

```
platform/
├── sources/           every HelmRepository, owned by one Kustomization
├── namespaces/        every platform namespace, with its Pod Security labels
├── infrastructure/    the cluster does not work without these
├── observability/     metrics, logs, runtime events
└── policy/            what may be admitted, and what may talk to what
```

Each directory under those is one Flux `Kustomization`, one `HelmRelease`, and
a `kustomization.yaml` that lists the files. The ordering between them is
declared in the cluster's files, not implied by the directory structure.

## What is installed

### Infrastructure

| Component | Why it is not optional |
|---|---|
| [AWS cloud controller manager](https://github.com/kubernetes/cloud-provider-aws) | Talos runs with `cloud-provider=external`, so every node registers tainted `node.cloudprovider.kubernetes.io/uninitialized`. This is what sets `providerID`, labels the node with its zone, and removes the taint. Nothing else schedules until it has. |
| [cert-manager](https://cert-manager.io) | Issues Hubble's mTLS from the trust anchor Terraform generates. |
| [Cilium](https://cilium.io) | CNI, kube-proxy replacement and, after this repository upgrades it, WireGuard encryption in strict mode and Hubble. |
| [kubelet-csr-approver](https://github.com/postfinance/kubelet-csr-approver) | Approves kubelet serving certificate requests, which kube-controller-manager will not. The Terraform module's `hardening.kubelet_serving_certificates` depends on it. |
| [metrics-server](https://github.com/kubernetes-sigs/metrics-server) | `kubectl top` and the HorizontalPodAutoscaler. |
| [AWS EBS CSI driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver) | Block storage, and the cluster's default StorageClass. |
| [Karpenter](https://karpenter.sh) | Node autoscaling. The worker autoscaling group is a fixed baseline; everything above it is Karpenter's. |

The Prometheus operator's CRDs are installed here too, ahead of the
observability layer, because Cilium declares `ServiceMonitor` objects and Helm
fails a release whose CRD does not exist.

### Observability

kube-prometheus-stack, Loki in its single-binary shape on an EBS volume, Alloy
collecting pod logs through the Kubernetes API rather than from hostPath, and
Tetragon.

### Policy

Kyverno, the cluster policies `docs/hardening.md` in the Terraform repository
lists as owed by this one, and a default-deny ingress `CiliumNetworkPolicy`
per platform namespace. **The Kyverno policies audit rather than block.** See
[`platform/policy/kyverno-policies/README.md`](platform/policy/kyverno-policies/README.md)
for how to move one to `Enforce`.

## Adding a cluster

Copy the template and commit it *before* `terraform apply`:

```sh
cp -r clusters/template clusters/my-cluster
git add clusters/my-cluster && git commit -m "Add my-cluster" && git push
```

Then apply with `project_name = "my-cluster"`. See
[`clusters/README.md`](clusters/README.md).

## What was removed

This repository used to carry a second cluster and a wider set of
applications. The cluster is gone, and with it Linkerd (Cilium does what it
was there for), cluster-autoscaler (replaced by Karpenter), auto-provider-id
(the cloud controller sets `providerID` itself now that nodes register with
their FQDN), and the applications that belonged to the other cluster rather
than to the platform.

## Development

```sh
./scripts/validate.sh
```

Builds every kustomization, renders every `HelmRelease` against the chart it
names, and validates the result against the Kubernetes and CRD schemas. It is
what CI runs. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
