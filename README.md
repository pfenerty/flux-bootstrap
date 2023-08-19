# Flux Bootstrap

Repo with flux configuration to bootstrap app for a cluster

Used with the [Talos AWS Terraform Repository](https://github.com/pfenerty/talos-aws-terraform) which creates a cluster and all of thes secrets that the applications rely on for install

Apps:

* [Auto Provider ID](https://github.com/pfenerty/auto-provider-id) - Self build app for automatically setting the `providerID` on nodes, to be used by the AWS cloud controller

* [AWS Cloud Controller](https://github.com/kubernetes/cloud-provider-aws) - cloud provider

* [AWS EBS CSI Driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver) - storage

* [Cert Manager](https://cert-manager.io/) - certificate management

* [Cilium](https://cilium.io/) - CNI, service mesh, ingress controller, gateway API provider, monitoring

* [Cluster Autoscaler](https://github.com/kubernetes/autoscaler) - cluster autoscaling

* [Linkerd](https://linkerd.io/) - service mesh

* [Loki Stack](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack) - logging

* [Kube Prometheus Stack](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/README.md) - monitoring