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

// Various opinionated helper functions, that might not be generally
// useful in other deployments.
local kube = import "kube.libsonnet";

{
  path_join(prefix, suffix):: (
    if std.endsWith(prefix, "/") then prefix + suffix
    else prefix + "/" + suffix
  ),

  trimUrl(str):: (
    if std.endsWith(str, "/") then
      std.substr(str, 1, std.length(str) - 1)
    else
      str
  ),

  toJson(x):: (
    if std.type(x) == "string" then std.escapeStringJson(x)
    else std.toString(x)
  ),

  subdomain(fqdn):: (
    local parts = std.split(fqdn, ".");
    local tail = [parts[i] for i in std.range(1, std.length(parts)-1)];
    std.join(".", tail)
  ),

  TlsIngress(name):: kube.Ingress(name) {
    local this = self,
    metadata+: {
      annotations+: {
        "kubernetes.io/tls-acme": "true",
        "kubernetes.io/ingress.class": "nginx",
      },
    },
    spec+: {
      tls+: [{
        hosts: std.set([r.host for r in this.spec.rules]),
        secretName: this.metadata.name + "-tls",
      }],
    },
  },

  AuthIngress(name):: $.TlsIngress(name) {
    local this = self,
    host:: error "host is required",
    metadata+: {
      annotations+: {
        // NB: Our nginx-ingress no-auth-locations includes "/oauth2"
        "nginx.ingress.kubernetes.io/auth-signin": "https://%s/oauth2/start" % this.host,
        "nginx.ingress.kubernetes.io/auth-url": "https://%s/oauth2/auth" % this.host,
        "nginx.ingress.kubernetes.io/auth-response-headers": "X-Auth-Request-User, X-Auth-Request-Email",
      },
    },

    spec+: {
      rules+: [{
        // This is required until the oauth2-proxy domain whitelist
        // feature (or similar) is released.  Until then, oauth2-proxy
        // *only supports* redirects to the same hostname (because we
        // don't want to allow "open redirects" to just anywhere).
        host: this.host,
        http: {
          paths: [{
            path: "/oauth2",
            backend: {
              // TODO: parameterise this based on oauth2 deployment
              serviceName: "oauth2-proxy",
              servicePort: 4180,
            },
          }],
        },
      }],
    },
  },
}
