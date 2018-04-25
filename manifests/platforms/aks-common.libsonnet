local kube = import "kube.libsonnet";
local cert_manager = import "cert-manager.jsonnet";
local edns = import "externaldns.jsonnet";
local nginx_ingress = import "nginx-ingress.jsonnet";
local prometheus = import "prometheus.jsonnet";
local heapster = import "heapster.jsonnet";
local oauth2_proxy = import "oauth2-proxy.jsonnet";
local fluentd_es = import "fluentd-es.jsonnet";
local elasticsearch = import "elasticsearch.jsonnet";
local kibana = import "kibana.jsonnet";

local az_dns_zone = std.extVar("DNS_SUFFIX");

{
  edns: edns {
    azconf:: kube.Secret(self.p+"external-dns-azure-config") + self.namespace {
      // to be filled in by installer
    },

    deploy+: {
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

  cert_manager: cert_manager,

  nginx_ingress: nginx_ingress,

  oauth2_proxy: oauth2_proxy {
    local oauth2 = self,

    secret+: {
      data_+: {
        azure_tenant: error "azure_tenant is required",  // filled by installer
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
      host: "prometheus." + az_dns_zone,
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
      host: "kibana." + az_dns_zone,
    },
  },
}
