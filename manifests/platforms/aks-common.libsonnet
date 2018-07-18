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
  edns: edns {
    azconf: kube.Secret("external-dns-azure-conf") {
      metadata+: {namespace: "kube-system"},
      data_+: {
        externalDns:: $.aksConfig.externalDns,
        "azure.json": std.manifestJsonEx(self.externalDns, "  "),
      },
    },

    deploy+: {
      ownerId: $.aksConfig.dnsZone,
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
    letsencrypt_contact_email:: $.aksConfig.contactEmail,
  },

  nginx_ingress: nginx_ingress,

  oauth2_proxy: oauth2_proxy {
    local oauth2 = self,

    secret+: {
      // created by installer (see kubeprod/pkg/aks/platform.go)
      metadata+: {namespace: "kube-system", name: "oauth2-proxy"},
      data_+: {
        client_id: $.aksConfig.oauthProxy.client_id,
        client_secret: $.aksConfig.oauthProxy.client_secret,
        cookie_secret: $.aksConfig.oauthProxy.cookie_secret,
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
                  "azure-tenant": $.aksConfig.oauthProxy.azure_tenant,
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
      host: "prometheus." + $.aksConfig.dnsZone,
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
      host: "kibana." + $.aksConfig.dnsZone,
    },
  },
}
