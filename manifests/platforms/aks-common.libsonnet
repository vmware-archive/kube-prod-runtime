local kube = import "kube.libsonnet";
local cert_manager = import "cert-manager.jsonnet";
local edns = import "externaldns.jsonnet";
local nginx_ingress = import "nginx-ingress.jsonnet";
local prometheus = import "prometheus.jsonnet";
local heapster = import "heapster.jsonnet";
local oauth2_proxy = import "oauth2-proxy.jsonnet";

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
        azure_tenant: error "azure_tenant is required",
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
      // FIXME: parameterise!
      host: "prometheus.aztest.oldmacdonald.farm",
    },
  },
}
