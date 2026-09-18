# Cluster policy

The rules `docs/hardening.md` in the Terraform module lists as owed by this
repository, written as Kyverno policies.

**Every one of them audits rather than blocks.** `failureAction: Audit`
records a violation in a PolicyReport and admits the resource. That is the
right setting to add a policy in and the wrong one to leave it in: switch a
rule to `Enforce` once `kubectl get policyreport -A` is clean for it, one rule
at a time.

```sh
kubectl get clusterpolicyreport
kubectl get policyreport -A
kubectl describe policyreport -n <namespace>
```

`kube-system` and `flux-system` are excluded from all of them. Both are
platform namespaces whose contents are not ours to change - Talos owns one
and Flux the other - and a policy that reports on them reports the same
violations forever.

| Policy | STIG rule | What it asks for |
|---|---|---|
| `require-namespace-psa-labels` | V-242437 | Every namespace carries an explicit Pod Security `enforce` label |
| `disallow-default-service-account` | V-242381 | Workloads run as a service account of their own, not `default` |
| `restrict-secrets-in-env-vars` | V-242415 | Secrets are mounted, not passed through the environment |
| `disallow-host-ports` | V-242414 | No workload binds a port on the node |
| `disallow-kubernetes-dashboard` | V-242395 | The Kubernetes dashboard is not deployed |
