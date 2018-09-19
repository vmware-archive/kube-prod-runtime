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
  config:: error "no kubeprod configuration",

  external_dns_zone_name:: $.config.dnsZone,
  letsencrypt_contact_email:: $.config.contactEmail,
  letsencrypt_environment:: "prod",

  edns: edns {
    azconf: kube.Secret(edns.p+"external-dns-azure-conf") + edns.namespace {
      data_+: {
        azure:: $.config.externalDns,
        "azure.json": std.manifestJson(self.azure),
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
    letsencrypt_environment:: $.letsencrypt_environment,
  },

  nginx_ingress: nginx_ingress,

  oauth2_proxy: oauth2_proxy {
    local oauth2 = self,

    secret+: {
      data_+: $.config.oauthProxy,
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

  heapster: heapster {
    deployment+: {
      metadata+: {
        labels+: {
          // The heapster pod was constantly being relaunched delaying the rollout on AKS
          // adding the // addon-manager label "EnsureExists" works around this issue
          // monitor https://github.com/Azure/ACS/issues/49 for issue resolution in AKS
          "addonmanager.kubernetes.io/mode": "EnsureExists",
        },
      },
    },
  },

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
