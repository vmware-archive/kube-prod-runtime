local kube = import "../lib/kube.libsonnet";

local NGNIX_INGRESS_IMAGE = "bitnami/nginx-ingress-controller:0.19.0-r8";

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  config: kube.ConfigMap($.p + "nginx-ingress") + $.metadata {
    data+: {
      "proxy-connect-timeout": "15",
      "disable-ipv6": "false",

      "hsts": "true",
      //"hsts-include-subdomains": "false",

      "enable-vts-status": "true",

      // TODO: move our oauth2-proxy path to something unlikely to clash with application URLs
      noauth:: ["/.well-known/acme-challenge", "/oauth2"],
      "no-auth-locations": std.join(",", std.set(self.noauth)),
    },
  },

  tcpconf: kube.ConfigMap($.p + "tcp-services") + $.metadata {
  },

  udpconf: kube.ConfigMap($.p + "udp-services") + $.metadata {
  },

  default: {
    svc: kube.Service($.p + "default-http-backend") + $.metadata {
      target_pod: $.default.deploy.spec.template,
      port: 80,
    },

    deploy: kube.Deployment($.p + "default-http-backend") + $.metadata {
      spec+: {
        template+: {
          spec+: {
            terminationGracePeriodSeconds: 30,
            containers_+: {
              default: kube.Container("default-http-backend") {
                image: "gcr.io/google_containers/defaultbackend:1.4",
                readinessProbe: {
                  httpGet: {path: "/healthz", port: 8080, scheme: "HTTP"},
                  timeoutSeconds: 5,
                },
                livenessProbe: self.readinessProbe {
                  initialDelaySeconds: 30,
                },
                ports_+: {
                  default: {containerPort: 8080},
                },
                resources: {
                  limits: {cpu: "10m", memory: "20Mi"},
                  requests: self.limits,
                },
              },
            },
          },
        },
      },
    },
  },

  ingressControllerClusterRole: kube.ClusterRole($.p+"nginx-ingress-controller") {
    rules: [
      {
        apiGroups: [""],
        resources: ["configmaps", "endpoints", "nodes", "pods", "secrets"],
        verbs: ["list", "watch"],
      },
      {
        apiGroups: [""],
        resources: ["nodes"],
        verbs: ["get"],
      },
      {
        apiGroups: [""],
        resources: ["services"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses/status"],
        verbs: ["update"],
      },
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch"],
      },
    ],
  },

  ingressControllerRole: kube.Role($.p + "nginx-ingress-controller") + $.metadata {
    rules: [
      {
        apiGroups: [""],
        resources: ["configmaps", "pods", "secrets", "namespaces"],
        verbs: ["get"],
      },
      {
        apiGroups: [""],
        resources: ["configmaps"],
        local election_id = "ingress-controller-leader",
        local ingress_class = "nginx",
        resourceNames: ["%s-%s" % [election_id, ingress_class]],
        verbs: ["get", "update"],
      },
      {
        apiGroups: [""],
        resources: ["configmaps"],
        local election_id = "ingress-controller-leader",
        local ingress_class = "nginx-internal",
        resourceNames: ["%s-%s" % [election_id, ingress_class]],
        verbs: ["get", "update"],
      },
      {
        apiGroups: [""],
        resources: ["configmaps"],
        verbs: ["create"],
      },
      {
        apiGroups: [""],
        resources: ["endpoints"],
        verbs: ["get"], // ["create", "update"],
      },
    ],
  },

  ingressControllerClusterRoleBinding: kube.ClusterRoleBinding($.p+"nginx-ingress-controller") {
    roleRef_: $.ingressControllerClusterRole,
    subjects_: [$.serviceAccount],
  },

  ingressControllerRoleBinding: kube.RoleBinding($.p + "nginx-ingress-controller") + $.metadata {
    roleRef_: $.ingressControllerRole,
    subjects_: [$.serviceAccount],
  },

  serviceAccount: kube.ServiceAccount($.p + "nginx-ingress-controller") + $.metadata {
  },

  svc: kube.Service($.p + "nginx-ingress") + $.metadata {
    target_pod: $.controller.spec.template,
    spec+: {
      ports: [
        {name: "http", port: 80, protocol: "TCP"},
        {name: "https", port: 443, protocol: "TCP"},
      ],
      type: "LoadBalancer",
      externalTrafficPolicy: "Local", // preserve source IP (where supported)
    },
  },

  hpa: kube.HorizontalPodAutoscaler($.p + "nginx-ingress-controller") + $.metadata {
    target: $.controller,
    spec+: {maxReplicas: 10},
  },

  controller: kube.Deployment($.p + "nginx-ingress-controller") + $.metadata {
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "10254",
            "prometheus.io/path": "/metrics",
          }
        },
        spec+: {
          serviceAccountName: $.serviceAccount.metadata.name,
          //hostNetwork: true, // access real source IPs, IPv6, etc
          terminationGracePeriodSeconds: 60,
          containers_+: {
            default: kube.Container("nginx") {
              image: NGNIX_INGRESS_IMAGE,
              securityContext: {
                runAsUser: 1001,
                capabilities: {
                  drop: ['ALL'],
                  add: ['NET_BIND_SERVICE'],
                },
              },
              env_+: {
                POD_NAME: kube.FieldRef("metadata.name"),
                POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              args_+: {
                local fqname(o) = "%s/%s" % [o.metadata.namespace, o.metadata.name],
                "default-backend-service": fqname($.default.svc),
                configmap: fqname($.config),
                // publish-service requires Service.Status.LoadBalancer.Ingress
                "publish-service": fqname($.svc),
                "tcp-services-configmap": fqname($.tcpconf),
                "udp-services-configmap": fqname($.udpconf),
                "sort-backends": true,
                //"ingress-class": "kubeprod.bitnami.com/nginx",
              },
              ports_: {
                http: {containerPort: 80},
                https: {containerPort: 443},
              },
              readinessProbe: {
                httpGet: {path: "/healthz", port: 10254, scheme: "HTTP"},
                failureThreshold: 3,
                periodSeconds: 10,
                successThreshold: 1,
                timeoutSeconds: 1,
              },
              livenessProbe: self.readinessProbe {
                initialDelaySeconds: 10,
              },
              resources+: {
                requests+: {cpu: "100m"},
              },
            },
          },
        },
      },
    },
  },
}
