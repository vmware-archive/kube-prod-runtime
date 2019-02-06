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

  parentDomain(fqdn):: (
    local parts = std.split(fqdn, ".");
    local tail = [parts[i] for i in std.range(1, std.length(parts)-1)];
    assert std.length(tail) >= 1 : "Tried to use parent of top-level DNS domain %s" % fqdn;
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
    authHost:: "auth." + $.parentDomain(this.host),
    metadata+: {
      annotations+: {
        // NB: Our nginx-ingress no-auth-locations includes "/oauth2"
        "nginx.ingress.kubernetes.io/auth-signin": "https://%s/oauth2/start?rd=%%2F$server_name$escaped_request_uri" % this.authHost,
        "nginx.ingress.kubernetes.io/auth-url": "https://%s/oauth2/auth" % this.authHost,
        "nginx.ingress.kubernetes.io/auth-response-headers": "X-Auth-Request-User, X-Auth-Request-Email",
      },
    },
  },
}
