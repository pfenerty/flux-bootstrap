# Network policy

A default-deny on ingress for each namespace this repository owns, with the
four things that legitimately reach into them allowed back in.

`CiliumNetworkPolicy` rather than the core `NetworkPolicy`, for one reason:
`fromEntities`. A core NetworkPolicy can only name pods, namespaces and CIDRs,
and the API server reaching a webhook is none of those - it arrives from a
node address, which would have to be written as an `ipBlock` of addresses that
change when the control plane is replaced. Cilium has a name for it.

What is allowed in:

* the same namespace, so a stack can talk to itself;
* `kube-apiserver`, without which every admission and conversion webhook
  fails, and with it every request that touches the resources they serve;
* `host` and `remote-node`, which covers the kubelet's probes and
  `kubectl port-forward`;
* `health`, which is Cilium's own connectivity checker;
* the `observability` namespace, so Prometheus can scrape.

Egress is deliberately left alone - `enableDefaultDeny.egress: false` on each
policy. A default-deny on egress has to allow DNS, the API server, every
upstream a controller pulls from and every AWS endpoint an SDK calls, and
getting one of those wrong fails in a way that looks like a bug in the
workload rather than a policy. Worth doing, one namespace at a time, after
watching Hubble for what each actually talks to:

```sh
cilium hubble port-forward &
hubble observe --namespace cert-manager --to-namespace kube-system
```

`kube-system` has no policy here at all. It holds the CNI, the cloud
controller, the CSI driver and Karpenter, all of which talk to the node, the
API server and the EC2 API in ways that a mistake would make the cluster
unrecoverable rather than merely broken.
