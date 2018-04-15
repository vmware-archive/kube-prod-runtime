// Various opinionated helper functions, that might not be generally
// useful in other deployments.
local kube = import "kube.libsonnet";

{
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
      annotations+: {"kubernetes.io/tls-acme": "true"},
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
        "kubernetes.io/ingress.class": "nginx",
        "nginx.ingress.kubernetes.io/auth-signin": "https://%s/oauth2/start" % this.host,
        "nginx.ingress.kubernetes.io/auth-url": "https://%s/oauth2/auth" % this.host,
      },
    },

    // Same as AuthIngress, only without the auth-url annotations.
    // This mess is required until the oauth2-proxy domain whitelist
    // feature (or similar) is released.  Until then, oauth2-proxy
    // *only supports* redirects to the same hostname (because we
    // don't want to allow "open redirects" to just anywhere.
    // TODO: refactor, to make the 2-Ingress-thing easier to consume.
    OauthIngress:: $.TlsIngress(this.metadata.name + "-oauth") {
      metadata+: {namespace: this.metadata.namespace},
      spec+: {
        rules+: [
          {
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
          },
        ],
        tls: this.spec.tls,
      },
    },
  },
}
