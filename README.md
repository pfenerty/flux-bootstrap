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

| Object | Namespace | Read by |
|---|---|---|
| `cilium-config` secret | `flux-system` | Cilium, for the strict-mode encryption CIDR. It has to match the pod CIDR the machine configs were generated with. |
| `karpenter-config` secret | `flux-system` | Karpenter's `HelmRelease`, and the `EC2NodeClass` and `NodePool` chart |
| `hubble-trust-anchor` secret | `kube-system` | cert-manager, as the CA the Hubble `Issuer` signs from |
| `cloud-controller-manager-aws-config` ConfigMap | `kube-system` | The cloud controller manager, as its `--cloud-config` and its AWS shared config |
| `ebs-csi-driver-aws-config` ConfigMap | `kube-system` | The EBS CSI controller's environment |
| `karpenter-aws-config` ConfigMap | `kube-system` | The Karpenter controller's environment |

`aws-loadbalancer-config` is also written by Terraform and read by nothing
here.

## AWS credentials, or the absence of them

Nothing here holds an AWS key pair. The cloud controller manager, the EBS CSI
driver and Karpenter each assume an IAM role by presenting a service account
token the cluster signed - IRSA, against an OpenID Connect provider Terraform
registers from the cluster's own discovery documents.

Each of the three gets the same two things:

* a projected `serviceAccountToken` volume, mounted at
  `/var/run/secrets/aws/token`, with `audience: sts.amazonaws.com` - which is
  not optional, and is what stops a token minted for the API server being
  replayed against IAM;
* the role ARN and that token path, from the ConfigMap Terraform writes,
  because both are specific to one cluster and nothing under `platform/` is.

The token path appears in both repositories and nothing checks that the two
agree. A mismatch fails at `AssumeRoleWithWebIdentity`, in the workload's
logs.

**No pod can read the instance metadata service.** The nodes' launch templates
set an IMDS hop limit of 1, which is what makes a role scoped to one service
account mean anything - otherwise any pod could ask metadata for the node's
credentials instead. Two consequences show up here: the cloud controller
manager is given its region and VPC in a cloud config file rather than
discovering them, and the EBS CSI node plugin is set to read its instance
facts from the Kubernetes API. Anything added later that expects IMDS will not
work.

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
| [tuppr](https://github.com/home-operations/tuppr) | Upgrades Talos and Kubernetes in place, node by node. Neither is Terraform's to sequence; see below. |

The Prometheus operator's CRDs are installed here too, ahead of the
observability layer, because Cilium declares `ServiceMonitor` objects and Helm
fails a release whose CRD does not exist.

#### Upgrades

A Talos or Kubernetes version bump is one pull request, against the Terraform
repository, changing `talos_version` or `kubernetes_version`. Applying it puts
the new AMI in the launch templates - so anything the autoscaling groups or
Karpenter launch from then on boots the new version already - and writes both
values into `flux-system/cluster-versions`.

This repository does the running fleet. `talos-upgrades` is a `TalosUpgrade`
and a `KubernetesUpgrade` with the two versions substituted in from that
ConfigMap, and tuppr reconciles them: drain, upgrade, reboot, verify, one node
at a time, one upgrade cluster-wide at a time. It drives each node's upgrade
from a Job pinned away from that node, so it never takes down the node it is
running on.

Nothing here decides *which* version is safe. tuppr upgrades to exactly what
it is given and does not enforce Talos's supported upgrade path, so stepping
one minor at a time is a review-time obligation on the Terraform pull request.

Two things worth knowing:

* **A green Terraform apply does not mean the cluster has moved.** It returns
  once the AMI and the ConfigMap are in place. `kubectl get talosupgrade -w`
  is what says otherwise.
* **The upgrade Jobs run as their namespace's `default` service account**,
  which `disallow-default-service-account` reports on. tuppr sets one only on
  hook Jobs. The policy audits rather than blocks, so nothing breaks, but
  `tuppr-system` will not go clean for that rule - which matters if you intend
  to move it to `Enforce`, and the exclusion would have to be deliberate.

`tuppr-system` is deliberately not the upstream quickstart's `system-upgrade`.
The namespace is the whole of the granularity Talos offers on
`kubernetesTalosAPIAccess`, the controller's credential is an ordinary Secret
in it, and `system-upgrade` is a name other operators install into. See
`docs/hardening.md` in the Terraform repository for what that grant costs.

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
names, and validates the result against the Kubernetes and CRD schemas. The
GitHub Actions workflow that runs it is in [`ci/validate.yaml`](ci/validate.yaml)
and has to be moved to `.github/workflows/validate.yaml` before it will run.
See [`CONTRIBUTING.md`](CONTRIBUTING.md).
