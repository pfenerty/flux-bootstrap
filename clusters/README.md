# Clusters

One directory per cluster. Its name is the cluster's `project_name` in the
Terraform module, because that is the path Flux is bootstrapped at:

```hcl
path = "clusters/${var.cluster.project_name}"
```

Each directory holds Flux `Kustomization` objects and nothing else - what this
cluster runs, in what order, and from which paths under `platform/`. The
manifests themselves are shared; the choice of which layers a cluster gets is
the only thing that lives here.

## Adding a cluster

Before `terraform apply`, not after:

```sh
cp -r clusters/template clusters/my-cluster
git add clusters/my-cluster
git commit -m "Add my-cluster"
git push
```

Then apply with `project_name = "my-cluster"`. `flux_bootstrap_git` writes
`clusters/my-cluster/flux-system` into this repository, commits it, and the
cluster syncs the whole directory - the three files that were already there
included. Apply first and the cluster comes up with Flux installed and
nothing else, until you push the files and it catches up on the next
reconcile.

`flux-system/` is generated. Do not edit it; `flux_bootstrap_git` rewrites it
on every apply, and the one thing that has to change about it - the
toleration every Flux Deployment needs for the uninitialized taint - is
applied by the Terraform module through `kustomization_override`.

## Dropping a layer

Delete the file. `observability.yaml` and `policy.yaml` are each
self-contained, and `prune: true` on the Kustomizations means removing the
file removes what it installed.

`infrastructure.yaml` is not optional in the same way. Everything in it is
either load-bearing for the cluster or a dependency of the other two.
