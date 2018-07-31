# Test AKS 1.8

(import "../platforms/aks+k8s-1.8.jsonnet") {
  "letsencrypt_contact_email": "noone@nowhere.com",
  config: {
    dnsZone: "test.example.com",
    externalDns: {
      tenantId: "mytenant",
      subscriptionId: "mysubscription",
      aadClientId: "myclientid",
      aadClientSecret: "mysecret",
      resourceGroup: "test-resource-group",
    },
    oauthProxy: {
      client_id: "myclientid",
      client_secret: "mysecret",
      cookie_secret: "cookiesecret",
      azure_tenant: "mytenant",
    },
  },
}
