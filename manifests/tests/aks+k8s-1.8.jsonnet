# Test AKS 1.8

(import "../platforms/aks+k8s-1.8.jsonnet") {
	    "cluster": "test",
        "external_dns_zone_name": "test.example.com",
        "letsencrypt_contact_email": "noone@nowhere.com",
}