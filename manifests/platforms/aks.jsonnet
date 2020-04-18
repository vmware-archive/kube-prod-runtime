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

// Top-level file for Azure AKS

local version = import "../components/version.jsonnet";

{
  lib+:: {
    kube: import "../lib/kube.libsonnet",
    utils: import "../lib/utils.libsonnet",
  },
  components:: (import "../components/components.jsonnet") {
    lib:: $.lib,
  },
  config:: error "no kubeprod configuration",

  // Shared metadata for all components
  kubeprod: $.lib.kube.Namespace("kubeprod"),

  external_dns_zone_name:: $.config.dnsZone,
  letsencrypt_contact_email:: $.config.contactEmail,
  letsencrypt_environment:: "prod",

  version: version,

  grafana: $.components.grafana {
    prometheus:: $.prometheus.prometheus.svc,
    ingress+: {
      host: "grafana." + $.external_dns_zone_name,
    },
  },

  edns: $.components.edns {
    azconf: $.lib.utils.HashedSecret(edns.p + "external-dns-azure-conf") {
      metadata+: { namespace: "kubeprod" },
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
              azconf: $.common.lib.kube.SecretVolume($.edns.azconf),
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

  cert_manager: $.components.cert_manager {
    letsencrypt_contact_email:: $.letsencrypt_contact_email,
    letsencrypt_environment:: $.letsencrypt_environment,
  },

  nginx_ingress: $.components.nginx_ingress,

  oauth2_proxy: $.components.oauth2_proxy {
    local oauth2 = self,

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
                  provider: "azure",
                },
                env_+: {
                  OAUTH2_PROXY_AZURE_TENANT: $.lib.kube.SecretKeyRef(oauth2.secret, "azure_tenant"),
                },
              },
            },
          },
        },
      },
    },
  },

  prometheus: $.components.prometheus {
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

  fluentd_es: $.components.fluentd_es {
    es:: $.elasticsearch,
  },

  elasticsearch: $.components.elasticsearch,

  kibana: $.components.kibana {
    es:: $.elasticsearch,
    ingress+: {
      host: "kibana." + $.external_dns_zone_name,
    },
  },
}
