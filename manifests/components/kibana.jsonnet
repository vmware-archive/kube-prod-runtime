local kube = import "../lib/kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "../lib/utils.libsonnet";

local KIBANA_IMAGE = "bitnami/kibana:5.6.11-r18";

local strip_trailing_slash(s) = (
  if std.endsWith(s, "/") then
    strip_trailing_slash(std.substr(s, 0, std.length(s) - 1))
  else
    s
);

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  es: error "elasticsearch is required",

  serviceAccount: kube.ServiceAccount($.p + "kibana") + $.metadata {
  },

  deploy: kube.Deployment($.p + "kibana") + $.metadata {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            kibana: kube.Container("kibana") {
              image: KIBANA_IMAGE,
              resources: {
                requests: {
                  cpu: "10m",
                },
                limits: {
                  cpu: "1000m", // initial startup requires lots of cpu
                },
              },
              env_+: {
                KIBANA_ELASTICSEARCH_URL: $.es.svc.host,

                local route = $.ingress.spec.rules[1].http.paths[0],
                // Make sure we got the correct route
                assert route.backend == $.svc.name_port,
                SERVER_BASEPATH: strip_trailing_slash(route.path),
                KIBANA_HOST: "0.0.0.0",
                XPACK_MONITORING_ENABLED: "false",
                XPACK_SECURITY_ENABLED: "false",
              },
              ports_+: {
                ui: { containerPort: 5601 },
              },
            },
          },
        },
      },
    },
  },

  svc: kube.Service($.p + "kibana-logging") + $.metadata {
    target_pod: $.deploy.spec.template,
  },

  ingress: utils.AuthIngress($.p + "kibana-logging") + $.metadata {
    local this = self,
    host:: error "host is required",
    spec+: {
      rules+: [
        {
          host: this.host,
          http: {
            paths: [
              { path: "/", backend: $.svc.name_port },
            ],
          },
        },
      ],
    },
  },
}
