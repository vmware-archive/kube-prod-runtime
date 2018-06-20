// Platform: Kubernetes 1.8.x on Azure AKS
//

(import "aks-common.libsonnet") {
  external_dns_zone_name:: "felipe.aztest.nami.run",
  cert_manager_email:: "felipe@bitnami.com",
}
