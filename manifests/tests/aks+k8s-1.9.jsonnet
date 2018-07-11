# Test AKS 1.9

local aks = import "../platforms/aks+k8s-1.9.jsonnet";

aks {
  azure_subscription:: "a",
  azure_tenant:: "b",
  edns_resource_group:: "c",
  edns_client_id:: "d",
  edns_client_secret:: "e",
  oauth2_client_id:: "f",
  oauth2_client_secret:: "g",
  oauth2_cookie_secret:: "h",
  external_dns_zone_name:: "i",
  letsencrypt_contact_email:: "j",
}
