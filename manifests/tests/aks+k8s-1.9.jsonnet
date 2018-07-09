# Test AKS 1.9

(import "../platforms/aks+k8s-1.9.jsonnet") {
        "external_dns_zone_name": "test.example.com",
        "letsencrypt_contact_email": "noone@nowhere.com",
}
