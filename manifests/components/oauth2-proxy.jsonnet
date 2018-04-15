local kube = import "kube.libsonnet";

{
  p:: "",
  namespace:: {metadata+: {namespace: "kube-system"}},

  secret:: kube.Secret($.p+"oauth2-proxy") + $.namespace {
    data_+: {
      client_id: error "client_id is required",
      client_secret: error "client_secret is required",
      cookie_secret: error "cookie_secret is required",
    },
  },

  svc: kube.Service($.p+"oauth2-proxy") + $.namespace {
    target_pod: $.deploy.spec.template,
    port: 4180,
  },

  hpa: kube.HorizontalPodAutoscaler($.p+"oauth2-proxy") + $.namespace {
    target: $.deploy,
    spec+: {maxReplicas: 10},
  },

  deploy: kube.Deployment($.p+"oauth2-proxy") + $.namespace {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            proxy: kube.Container("oauth2-proxy") {
              image: "a5huynh/oauth2_proxy:2.2.1",
              args_+: {
                "email-domain": "*",
                "http-address": "0.0.0.0:4180",
                "cookie-secure": "true",
                "cookie-refresh": "3h",
                "set-xauthrequest": true,
                "tls-cert": "",
                upstream: "file:///dev/null",
              },
              env_+: {
                OAUTH2_PROXY_CLIENT_ID: kube.SecretKeyRef($.secret, "client_id"),
                OAUTH2_PROXY_CLIENT_SECRET: kube.SecretKeyRef($.secret, "client_secret"),
                OAUTH2_PROXY_COOKIE_SECRET: kube.SecretKeyRef($.secret, "cookie_secret"),
              },
              ports_+: {
                http: {containerPort: 4180},
              },
              readinessProbe: {
                httpGet: {path: "/ping", port: "http"},
              },
              livenessProbe: self.readinessProbe,
            },
          },
        },
      },
    },
  },
}
