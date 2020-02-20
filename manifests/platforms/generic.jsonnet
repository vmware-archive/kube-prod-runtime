/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018-2019 Bitnami
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

// Top-level file for Google GKE

local kube = import "../lib/kube.libsonnet";
local utils = import "../lib/utils.libsonnet";
local version = import "../components/version.jsonnet";
local cert_manager = import "../components/cert-manager.jsonnet";
local edns = import "../components/externaldns.jsonnet";
local nginx_ingress = import "../components/nginx-ingress.jsonnet";
local prometheus = import "../components/prometheus.jsonnet";
local keycloak = import "../components/keycloak.jsonnet";
local oauth2_proxy = import "../components/oauth2-proxy.jsonnet";
local fluentd_es = import "../components/fluentd-es.jsonnet";
local elasticsearch = import "../components/elasticsearch.jsonnet";
local kibana = import "../components/kibana.jsonnet";
local grafana = import "../components/grafana.jsonnet";

{
  config:: error "no kubeprod configuration",

  // Shared metadata for all components
  kubeprod: kube.Namespace("kubeprod"),

  external_dns_zone_name:: $.config.dnsZone,
  letsencrypt_contact_email:: $.config.contactEmail,
  letsencrypt_environment:: "prod",

  version: version,

  grafana: grafana {
    prometheus:: $.prometheus.prometheus.svc,
    ingress+: {
      host: "grafana." + $.external_dns_zone_name,
    },
  },

  cert_manager: cert_manager {
    letsencrypt_contact_email:: $.letsencrypt_contact_email,
    letsencrypt_environment:: $.letsencrypt_environment,
  },

  nginx_ingress: nginx_ingress,

  oauth2_proxy: oauth2_proxy {
    secret+: {
      data_+: $.config.oauthProxy,
    },

    ingress+: {
      host: "auth." + $.external_dns_zone_name,
    },

    deploy+: {
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              proxy+: {
                args_+: {
                  "email-domain": $.config.oauthProxy.authz_domain,
                  provider: "keycloak",
                  "login-url": "https://id.%s/auth/realms/BKPR/protocol/openid-connect/auth" % $.external_dns_zone_name,
                  "redeem-url": "https://id.%s/auth/realms/BKPR/protocol/openid-connect/token" % $.external_dns_zone_name,
                  "validate-url": "https://id.%s/auth/realms/BKPR/protocol/openid-connect/userinfo" % $.external_dns_zone_name,
                },
              },
            },
          },
        },
      },
    },
  },

  keycloak: keycloak {
    oauth2_proxy:: $.oauth2_proxy,
    admin_password:: $.config.keycloak.password,
    client_id:: $.config.oauthProxy.client_id,
    client_secret:: $.config.oauthProxy.client_secret,
    ingress+: {
      host: "id." + $.external_dns_zone_name,
    },
  },

  prometheus: prometheus {
    ingress+: {
      host: "prometheus." + $.external_dns_zone_name,
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
