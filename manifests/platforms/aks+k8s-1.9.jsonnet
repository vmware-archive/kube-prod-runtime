// Platform: Kubernetes 1.9.x on Azure AKS
//

(import "aks-common.libsonnet") {
  az_dns_zone:: "felipe.aztest.nami.run",
  cert_manager_email:: "felipe@bitnami.com",
}
