local kube = import "kube.libsonnet";
local cert_manager = import "cert-manager.jsonnet";
local edns = import "externaldns.jsonnet";
local nginx_ingress = import "nginx-ingress.jsonnet";

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

  // prometheus
}
