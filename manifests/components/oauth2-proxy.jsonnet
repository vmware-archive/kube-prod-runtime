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

local kubecfg = import "kubecfg.libsonnet";
local kube = import "../lib/kube.libsonnet";
local utils = import "../lib/utils.libsonnet";

local OAUTH2_PROXY_IMAGE = (import "images.json")["oauth2_proxy"];

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  secret: utils.HashedSecret($.p + "oauth2-proxy") + $.metadata {
    data_+: {
      client_id: error "client_id is required",
      client_secret: error "client_secret is required",
      cookie_secret: error "cookie_secret is required",
    },
  },

  svc: kube.Service($.p + "oauth2-proxy") + $.metadata {
    target_pod: $.deploy.spec.template,
    port: 4180,
  },

  hpa: kube.HorizontalPodAutoscaler($.p + "oauth2-proxy") + $.metadata {
    target: $.deploy,
    spec+: {
      // Put a cap on growth due to (eg) DoS attacks.
      // Large sites will want to increase this to cover legitimate demand.
      maxReplicas: 10,
    },
  },

  pdb: kube.PodDisruptionBudget($.p + "oauth2-proxy") + $.metadata {
    target_pod: $.deploy.spec.template,
    spec+: {minAvailable: $.deploy.spec.replicas - 1},
  },

  ingress: utils.TlsIngress($.p + "oauth2-ingress") + $.metadata {
    local this = self,
    host:: error "host is required",

    metadata+: {
      annotations+: {
        // Restrict/extend this to match known+trusted sites within your oauth2-authenticated control.
        // NB: It is tempting to make this ".*" and just make it work for anything, but don't do this!
        // This will result in an open redirect vulnerability: https://www.owasp.org/index.php/Open_redirect
        allowedRedirectors:: "[^/]+\\." + kubecfg.escapeStringRegex(utils.parentDomain(this.host)),
        "nginx.ingress.kubernetes.io/configuration-snippet": |||
          location "~^/(?<target_host>%s)(?<remaining_uri>.*)$" {
            rewrite ^ $scheme://$target_host$remaining_uri;
          }
        ||| % self.allowedRedirectors,
      },
    },

    spec+: {
      rules+: [{
        host: this.host,
        http: {
          paths: [
            { path: "/oauth2/", backend: $.svc.name_port },
            // The "/" block is only used for the location regex rewrite
            { path: "/", backend: $.svc.name_port },
          ],
        },
      }],
    },
  },

  deploy: kube.Deployment($.p + "oauth2-proxy") + $.metadata {
    local this = self,
    spec+: {
      // Ensure at least n+1.  NB: HPA will increase replicas dynamically.
      replicas: 2,
      template+: {
        spec+: {
          affinity+: utils.weakNodeDiversity(this.spec.selector),
          containers_+: {
            proxy: kube.Container("oauth2-proxy") {
              image: OAUTH2_PROXY_IMAGE,
              args_+: {
                "email-domain": "*",
                "http-address": "0.0.0.0:4180",
                "cookie-secure": "true",
                "cookie-refresh": "3h",
                "set-xauthrequest": true,
                "tls-cert": "",
                "upstream": "file:///dev/null",
                "redirect-url": "https://%s/oauth2/callback" % $.ingress.host,
                "cookie-domain": utils.parentDomain($.ingress.host),
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
              livenessProbe: self.readinessProbe {
                initialDelaySeconds: 30,
              },
              resources+: {
                requests+: {cpu: "10m"},
              },
            },
          },
        },
      },
    },
  },
}
