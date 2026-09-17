# Contributing

## Before you push

```sh
./scripts/validate.sh
```

It builds every kustomization, validates the result against the Kubernetes
and CRD schemas, and renders every `HelmRelease` against the chart it names -
which is the check that catches a yanked chart version, a moved repository,
or a value the chart's own schema rejects. It needs `helm`, `kustomize`,
`kubeconform` and `yq` on `PATH`, talks to no cluster, and is what CI runs.

## Conventions

* **One directory per component**, holding a `kustomization.yaml` that lists
  its files, and one Flux `Kustomization` in the cluster directory pointing at
  it. The `kustomization.yaml` is not optional even where kustomize-controller
  would generate one: without it `kustomize build` cannot validate the
  directory, and a file that is not listed is a file that silently does not
  deploy.

* **`HelmRelease` objects live in `flux-system`** and install into their
  `targetNamespace`. That is what lets `valuesFrom` read the secrets Terraform
  writes into `flux-system`, which is where several of them are.

* **Chart versions are exact.** Renovate bumps them and CI renders the result
  before it merges. A range would mean the cluster's contents depend on when
  it last reconciled.

* **Health checks name the `HelmRelease`, not the Deployment it produces.** A
  `HelmRelease` goes ready when Helm's own wait has seen the workloads become
  available, so it means the same thing without hard-coding a name the chart
  is free to change - which is how the previous version of this repository
  ended up checking a Deployment called
  `kube-system-cluster-autoscaler-aws-cluster-autoscaler`.

* **`dependsOn` states what actually blocks what**, and carries a comment when
  the reason is not obvious from the names. Ordering that exists only to make
  the logs tidy is not a dependency.

* **Nothing cluster-specific in `platform/`.** Cluster values arrive in the
  secrets Terraform writes; the only per-cluster files are the Flux
  `Kustomization` objects under `clusters/<name>/`.

* **No secrets in this repository**, encrypted or otherwise. Everything
  sensitive is created by Terraform, which already holds it in state. There is
  no SOPS setup here and adding one should be a deliberate decision rather
  than a convenience.

* **Comments say why, not what.** `kubectl explain` covers what a field is.
  The reason a value is set to something other than the chart default is the
  thing that is lost otherwise, and most of the values in this repository are
  set for a reason that is specific to Talos, to AWS, or to the order things
  come up in.

## Changing the platform

Adding a component:

1. A directory under `platform/<layer>/<component>` with `release.yaml` and
   `kustomization.yaml`.
2. Its `HelmRepository` in `platform/sources/helm-repositories.yaml`, if it is
   not already there. One repository, one owner - two Kustomizations declaring
   the same source will fight over it.
3. A Flux `Kustomization` in `clusters/template/<layer>.yaml`, with
   `dependsOn` and a health check, and the same addition to any live cluster
   directory that should get it.
4. `./scripts/validate.sh`.

Removing one is the same in reverse. `prune: true` means deleting the
Kustomization removes what it installed, so check what holds data first - the
Prometheus, Grafana and Loki volumes are `Delete` reclaim policy.

## The Terraform side

Several things here only work because of a decision in
[pfenerty/talos-aws-terraform](https://github.com/pfenerty/talos-aws-terraform):
the secrets, the sync path, the Flux toleration patch, the bootstrap Cilium
release this repository adopts, and `registerWithFQDN` on the kubelet, without
which the cloud controller cannot find a node's instance. A change here that
needs one of those changed is a change to both repositories, and
`docs/hardening.md` there is where the obligations of this one are written
down.
