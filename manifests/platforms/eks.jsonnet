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

// Top-level file for AWS EKS

local kube = import '../lib/kube.libsonnet';
local cert_manager = import '../components/cert-manager.jsonnet';
local edns = import '../components/externaldns.jsonnet';
local nginx_ingress = import '../components/nginx-ingress.jsonnet';
local prometheus = import "../components/prometheus.jsonnet";
local oauth2_proxy = import "../components/oauth2-proxy.jsonnet";
local fluentd_es = import "../components/fluentd-es.jsonnet";
local elasticsearch = import "../components/elasticsearch.jsonnet";
local kibana = import "../components/kibana.jsonnet";
local grafana = import "../components/grafana.jsonnet";

{
  config:: error 'no kubeprod configuration',

  // Shared metadata for all components
  kubeprod: kube.Namespace('kubeprod'),

  external_dns_zone_name:: $.config.dnsZone,
  letsencrypt_contact_email:: $.config.contactEmail,
  letsencrypt_environment:: 'prod',

  version: import '../components/version.jsonnet',

  grafana: grafana {
    prometheus:: $.prometheus.prometheus.svc,
    ingress+: {
      host: "grafana." + $.external_dns_zone_name,
    },
  },

  edns: edns {
    local this = self,

    // NOTE: https://docs.aws.amazon.com/sdk-for-go/v1/developer-guide/configuring-sdk.html#specifying-credentials
    // for additional information on how to use environment variables to configure a particular user when accessing
    // the AWS API.
    secret: kube.Secret(edns.p + "external-dns-aws-conf") {
      metadata+: {
        namespace: "kubeprod",
      },
      data_+: $.config.externalDns,
    },

    deploy+: {
      ownerId: $.external_dns_zone_name,
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              edns+: {
                env_+: {
                  AWS_ACCESS_KEY_ID: kube.SecretKeyRef(this.secret, "aws_access_key_id"),
                  AWS_SECRET_ACCESS_KEY: kube.SecretKeyRef(this.secret, "aws_access_key_secret"),
                },
                args_+: {
                  provider: 'aws',
                  'aws-zone-type': 'public',
                  registry: 'txt',
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
                  provider: 'oidc',
                  'oidc-issuer-url': 'https://cognito-idp.%s.amazonaws.com/%s' % [
                    $.config.oauthProxy.aws_region,
                    $.config.oauthProxy.aws_user_pool_id
                  ],
                  /* NOTE: disable cookie refresh token.
                   * As per https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html:
                   * The refresh token is defined in the specification, but is not currently implemented to
                   * be returned from the Token Endpoint.
                   */
                  'cookie-refresh': '0',
                },
              },
            },
          },
        },
      },
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

  elasticsearch: elasticsearch {
  },

  kibana: kibana {
    es:: $.elasticsearch,
    ingress+: {
      host: "kibana." + $.external_dns_zone_name,
    },
  },
}
