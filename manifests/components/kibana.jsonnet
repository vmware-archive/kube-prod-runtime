local kube = import "kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "utils.libsonnet";

local KIBANA_IMAGE = "docker.elastic.co/kibana/kibana:5.6.4";

local strip_trailing_slash(s) = (
  if std.endsWith(s, "/") then
    strip_trailing_slash(std.substr(s, 0, std.length(s) - 1))
  else
    s
);

{
  p:: "",
  namespace:: { metadata+: { namespace: "kube-system" } },

  es: error "elasticsearch is required",

  serviceAccount: kube.ServiceAccount($.p + "kibana") + $.namespace,

  deploy: kube.Deployment($.p + "kibana") + $.namespace {
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
                ELASTICSEARCH_URL: "http://%s:9200" % [$.es.svc.host],

                local route = $.ingress.spec.rules[0].http.paths[0],
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

  svc: kube.Service($.p + "kibana-logging") + $.namespace {
    target_pod: $.deploy.spec.template,
  },

  ingress: utils.AuthIngress($.p + "kibana-logging") + $.namespace {
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
  ingressOauth: $.ingress.OauthIngress,
}
