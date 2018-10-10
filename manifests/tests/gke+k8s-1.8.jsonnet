# Test GKE 1.8

(import "../platforms/gke+k8s-1.8.jsonnet") {
  "letsencrypt_contact_email": "noone@nowhere.com",
  config: {
    dnsZone: "test.example.com",
    externalDns: {
      credentials: "google credentials json contents",
      project: "dns_gcp_project",
    },
    oauthProxy: {
      client_id: "myclientid",
      client_secret: "mysecret",
      cookie_secret: "cookiesecret",
      google_groups: [],
      google_admin_email: "admin@example.com",
      google_service_account_json: "<fake google credentials json contents>",
    },
  },
}
