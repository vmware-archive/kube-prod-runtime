// Platform: Kubernetes 1.8.x on Azure AKS
//

(import "aks-common.libsonnet") {
  external_dns_zone_name:: std.extVar('DNS_SUFFIX'),
  letsencrypt_contact_email:: std.extVar('EMAIL'),
}
