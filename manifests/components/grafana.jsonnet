/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018 Bitnami
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

local kube = import "../lib/kube.libsonnet";
local utils = import "../lib/utils.libsonnet";

local GRAFANA_IMAGE = "bitnami/grafana:5.3.4-r6";

// TODO: add blackbox-exporter

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  // Default to "Editor".
  // User can create/modify dashboards & alert rules, but cannot create/edit
  // datasources nor invite new users
  auto_role:: "Editor",

  // Required to restrict login attempts to a particular domain
  email_domain:: error "Missing e-mail domain",

  // Google Bitnami oAuth secrets, sealed secrets under sre-kube-configs
  google_oauth_secret: kube.Secret($.p + "grafana-google-oauth") + $.metadata {
    data_+: {
      "google-client-id": error "provided externally",
      "google-client-secret": error "provided externally",
    },
  },

  grafana_admin_config: kube.Secret($.p + "grafana-admin-config") + $.metadata {
    data_+: {
      "grafana-admin-password": "admin",
    },
  },

  svc: kube.Service($.p + "grafana") + $.metadata {
    target_pod: $.grafana.spec.template,
  },

  ingress: utils.AuthIngress($.p + "grafana") + $.metadata {
    local this = self,
    host:: error "host required",
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

  grafana: kube.StatefulSet($.p + "grafana") + $.metadata {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            grafana: kube.Container("grafana") {
              image: GRAFANA_IMAGE,
              resources: {
                limits: { cpu: "100m", memory: "100Mi" },
                requests: self.limits,
              },
              ports_+: {
                dashboard: { containerPort: 3000 },
              },
              env_+: {
                GF_AUTH_BASIC_ENABLED: "true",
                GF_AUTH_ANONYMOUS_ENABLED: "true",
                GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer",
                GF_SERVER_DOMAIN: $.ingress.host,
                GF_SERVER_ROOT_URL: "https://" + $.ingress.host,
                GF_LOG_MODE: "console",
                GF_LOG_LEVEL: "warn",
                GF_METRICS_ENABLED: "true",
                GF_SECURITY_ADMIN_USER: "admin",
                GF_SECURITY_ADMIN_PASSWORD: kube.SecretKeyRef($.grafana_admin_config, "grafana-admin-password"),
                GF_AUTH_SIGNOUT_MENU: "true",
                GF_AUTH_GOOGLE_ENABLED: "true",
                GF_AUTH_GOOGLE_CLIENT_ID: kube.SecretKeyRef($.google_oauth_secret, "google-client-id"),
                GF_AUTH_GOOGLE_CLIENT_SECRET: kube.SecretKeyRef($.google_oauth_secret, "google-client-secret"),
                GF_AUTH_GOOGLE_SCOPES: "https://www.googleapis.com/auth/userinfo.profile, https://www.googleapis.com/auth/userinfo.email",
                GF_AUTH_GOOGLE_AUTH_URL: "https://accounts.google.com/o/oauth2/auth",
                GF_AUTH_GOOGLE_TOKEN_URL: "https://accounts.google.com/o/oauth2/token",
                GF_AUTH_GOOGLE_ALLOW_SIGN_UP: "true",
                GF_AUTH_GOOGLE_ALLOWED_DOMAINS: $.email_domain,
                GF_USERS_AUTO_ASSIGN_ORG_ROLE: $.auto_role,
                GF_USERS_AUTO_ASSIGN_ORG: "true",
                GF_EXPLORE_ENABLED: "true",
              },
              volumeMounts_+: {
                datadir: { mountPath: "/var/lib/grafana" },
              },
              livenessProbe: {
                httpGet: { path: "/api/org", port: "dashboard" },
                timeoutSeconds: 3,
              },
              readinessProbe: self.livenessProbe {
                successThreshold: 2,
              },
            },
          },
          securityContext: {
            // make pvc owned by this gid (Bitnami non-root gid)
            fsGroup: 1001,
          },
        },
      },
      volumeClaimTemplates_+: {
        datadir: {
          storage: "1Gi",
        },
      },
    },
  },
}