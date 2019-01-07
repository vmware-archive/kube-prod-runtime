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

local OAUTH2_PROXY_IMAGE = (import "images.json")["oauth2_proxy"];

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  secret: kube.Secret($.p + "oauth2-proxy") + $.metadata {
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
    spec+: {maxReplicas: 10},
  },

  deploy: kube.Deployment($.p + "oauth2-proxy") + $.metadata {
    spec+: {
      template+: {
        spec+: {
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
