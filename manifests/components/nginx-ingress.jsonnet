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

local NGNIX_INGRESS_IMAGE = (import "images.json")["nginx-ingress-controller"];

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
        local ingress_class = $.controller.spec.template.spec.containers_.default.args_["ingress-class"],
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
    spec+: {
      // Put a cap on growth due to (eg) DoS attacks.
      // Large sites will want to increase this to cover legitimate demand.
      maxReplicas: 10,
    },
  },

  pdb: kube.PodDisruptionBudget($.p + "nginx-ingress-controller") + $.metadata {
    target_pod: $.controller.spec.template,
    spec+: {minAvailable: $.controller.spec.replicas - 1},
  },

  controller: kube.Deployment($.p + "nginx-ingress-controller") + $.metadata {
    local this = self,
    spec+: {
      // Ensure at least n+1.  NB: HPA will increase replicas dynamically.
      replicas: 2,
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
          affinity+: utils.weakNodeDiversity(this.spec.selector),
          containers_+: {
            default: kube.Container("nginx") {
              image: NGNIX_INGRESS_IMAGE,
              securityContext: {
                runAsUser: 1001,
                capabilities: {
                  drop: ["ALL"],
                  add: ["NET_BIND_SERVICE"],
                },
              },
              env_+: {
                POD_NAME: kube.FieldRef("metadata.name"),
                POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              args_+: {
                local fqname(o) = "%s/%s" % [o.metadata.namespace, o.metadata.name],
                configmap: fqname($.config),
                // NB: publish-service requires Service.Status.LoadBalancer.Ingress
                // to be set correctly.
                "publish-service": fqname($.svc),
                "tcp-services-configmap": fqname($.tcpconf),
                "udp-services-configmap": fqname($.udpconf),
                "ingress-class": "nginx",
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
