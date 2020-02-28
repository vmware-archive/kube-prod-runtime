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

local kube = import "../lib/kube.libsonnet";
local utils = import "../lib/utils.libsonnet";
local version = import "../components/version.jsonnet";
local cert_manager = import "../components/cert-manager.jsonnet";
local pdns = import "../components/powerdns.jsonnet";
local edns = import "../components/externaldns.jsonnet";
local nginx_ingress = import "../components/nginx-ingress.jsonnet";
local prometheus = import "../components/prometheus.jsonnet";
local galera = import "../components/mariadb-galera.jsonnet";
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
  ssl_skip_verify:: if $.letsencrypt_environment == 'staging' then true else false,

  version: version,

  grafana: grafana {
    prometheus:: $.prometheus.prometheus.svc,
    ingress+: {
      host: "grafana." + $.external_dns_zone_name,
    },
  },

  pdns: pdns {
    zone: $.external_dns_zone_name,
    api_key:: $.config.powerDns.api_key,
    ingress+: {
      host: "pdns." + $.external_dns_zone_name,
    },
  },

  edns: edns {
    deploy+: {
      ownerId: $.external_dns_zone_name,
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              edns+: {
                args_+: {
                  provider: "pdns",
                  "pdns-server": "http://%s:%s" % [
                    $.pdns.svc.host,
                    $.pdns.svc.port,
                  ]
                },
                env_+: {
                  EXTERNAL_DNS_PDNS_API_KEY: kube.SecretKeyRef($.pdns.secret, "api_key"),
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

  nginx_ingress: nginx_ingress {
    local this = self,
    udpconf+: {
      data+: {
        "53": "%s/%s:53" % [
          $.pdns.svc.metadata.namespace,
          $.pdns.svc.metadata.name,
        ],
      }
    },
    udpsvc: kube.Service(this.p + "nginx-ingress-udp") + this.metadata {
      target_pod: this.controller.spec.template,
      spec+: {
        ports: [
          {name: "dns-udp", port: 53, protocol: "UDP"},
        ],
        type: "LoadBalancer",
        externalTrafficPolicy: "Cluster",
      },
    },
  },

  oauth2_proxy: oauth2_proxy {
    secret+: {
      data_+: $.config.oauthProxy + {
        client_id: $.config.keycloak.client_id,
        client_secret: $.config.keycloak.client_secret,
      },
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
                  "keycloak-group": $.config.keycloak.group,
                  "login-url": "https://id.%s/auth/realms/BKPR/protocol/openid-connect/auth" % $.external_dns_zone_name,
                  "redeem-url": "https://id.%s/auth/realms/BKPR/protocol/openid-connect/token" % $.external_dns_zone_name,
                  "validate-url": "https://id.%s/auth/realms/BKPR/protocol/openid-connect/userinfo" % $.external_dns_zone_name,
                  "ssl-insecure-skip-verify": $.ssl_skip_verify,
                },
              },
            },
          },
        },
      },
    },
  },

  galera: galera {
    secret+: {
      data_+: $.config.mariadbGalera,
    },
  },

  keycloak: keycloak {
    galera: $.galera,
    oauth2_proxy:: $.oauth2_proxy,
    secret+: {
      data_+: $.config.keycloak,
    },
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
