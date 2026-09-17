# Namespaces

Every namespace the platform owns, with its Pod Security Admission labels, in
one place - because the labels are the point.

The Terraform module's `hardening` sets the cluster-wide default with the
`PodSecurity` admission plugin, and exempts `kube-system` because Cilium runs
a privileged pod there and the cluster cannot become healthy without a CNI.
That is the cluster half of the control. The per-namespace half is here, and
it is the half a STIG or CIS review asks to see: an explicit level on every
namespace, set deliberately rather than inherited.

Three rules:

* `enforce` is a floor, not a description. A `privileged` namespace is one
  where something in it genuinely needs to be; it does not mean everything in
  it is.
* `audit` and `warn` stay at `restricted` even where `enforce` cannot, so a
  new workload that could have run restricted is still flagged.
* Anything raised above `restricted` needs a comment saying which workload
  forced it.

`kube-system` and `flux-system` are not here. Both are created before this
repository is reconciled - by Talos and by `flux bootstrap` respectively - and
`kube-system` is the exempted namespace, which is Terraform's to set.
