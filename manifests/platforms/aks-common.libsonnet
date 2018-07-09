local kube = import "../lib/kube.libsonnet";
local cert_manager = import "../components/cert-manager.jsonnet";
local edns = import "../components/externaldns.jsonnet";
local nginx_ingress = import "../components/nginx-ingress.jsonnet";
local prometheus = import "../components/prometheus.jsonnet";
local heapster = import "../components/heapster.jsonnet";
local oauth2_proxy = import "../components/oauth2-proxy.jsonnet";
local fluentd_es = import "../components/fluentd-es.jsonnet";
local elasticsearch = import "../components/elasticsearch.jsonnet";
local kibana = import "../components/kibana.jsonnet";

{
  azure_subscription:: error "azure_subscription is required",
  azure_tenant:: error "azure_tenant is required",
  edns_resource_group:: error "resource_group_name is required",
  edns_client_id:: error "edns_client_id is required",
  edns_client_secret:: error "edns_client_secret is required",
  oauth2_client_id:: error "oauth2_client_id is required",
  oauth2_client_secret:: error "oauth2_client_secret is required",
  oauth2_cookie_secret:: error "oauth2_cookie_secret is required",
  external_dns_zone_name:: error "External DNS zone name is undefined",
  letsencrypt_contact_email:: error "Letsencrypt contact e-mail is undefined",

  edns: edns {
    azconf: kube.Secret("external-dns-azure-conf") {
      metadata+: {namespace: "kube-system"},
      data_+: {
        "azure.json": std.manifestJsonEx({
            "tenantId": $.azure_tenant,
            "subscriptionId": $.azure_subscription,
            "aadClientId": $.edns_client_id,
            "aadClientSecret": $.edns_client_secret,
            "resourceGroup": $.edns_resource_group
        }, "  "),
      },
    },

    deploy+: {
      ownerId: $.external_dns_zone_name,
      spec+: {
        template+: {
          spec+: {
            volumes_+: {
              azconf: kube.SecretVolume($.edns.azconf),
            },
            containers_+: {
              edns+: {
                args_+: {
                  provider: "azure",
                  "azure-config-file": "/etc/kubernetes/azure.json",
                },
                volumeMounts_+: {
                  azconf: {mountPath: "/etc/kubernetes", readOnly: true},
                },
              },
            },
          },
        },
      },
    },
  },

  cert_manager: cert_manager {
    letsencrypt_contact_email:: $.letsencrypt_contact_email,
  },

  nginx_ingress: nginx_ingress,

  oauth2_proxy: oauth2_proxy {
    local oauth2 = self,

    secret+: {
      // created by installer (see kubeprod/pkg/aks/platform.go)
      metadata+: {namespace: "kube-system", name: "oauth2-proxy"},
      data_+: {
        azure_tenant: $.azure_tenant,
        client_id: $.oauth2_client_id,
        client_secret: $.oauth2_client_secret,
        cookie_secret: $.oauth2_cookie_secret,
      },
    },

    deploy+: {
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              proxy+: {
                args_+: {
                  provider: "azure",
                },
                env_+: {
                  OAUTH2_PROXY_AZURE_TENANT: kube.SecretKeyRef(oauth2.secret, "azure_tenant"),
                },
              },
            },
          },
        },
      },
    },
  },

  heapster: heapster,

  prometheus: prometheus {
    ingress+: {
      host: "prometheus." + $.external_dns_zone_name,
    },
    config+: {
      scrape_configs_+: {
        apiservers+: {
          // AKS firewalls off cluster jobs from reaching the APIserver
          // except via the kube-proxy.
          // TODO: see if we can just fix this by tweaking a NetworkPolicy
          kubernetes_sd_configs:: null,
          static_configs: [{targets: ["kubernetes.default.svc:443"]}],
          relabel_configs: [],
        },
      },
    },
  },

  fluentd_es: fluentd_es {
    es:: $.elasticsearch,
  },

  elasticsearch: elasticsearch,

  kibana: kibana {
    es:: $.elasticsearch,

    ingress+: {
      host: "kibana." + $.external_dns_zone_name,
    },
  },
}
