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
local EXTERNAL_DNS_IMAGE = (import "images.json")["external-dns"];

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  dnsEndpointCRD: kube.CustomResourceDefinition("externaldns.k8s.io", "v1beta1", "DNSEndpoint") {
    metadata+: {
      labels+: {
        api: "externaldns",
        "kubebuilder.k8s.io": "1.0.0",
      },
    },
    spec+: {
      subresources+: {
        status+: {},
      },
      validation+: {
        openAPIV3Schema+: {
          properties+: {
            apiVersion: {
              type: "string",
            },
            kind: {
              type: "string",
            },
            metadata: {
              type: "object",
            },
            spec+: {
              properties+: {
                endpoints+: {
                  items+: {
                    properties: {
                      dnsName: {
                        type: "string",
                      },
                      labels: {
                        type: "object",
                      },
                      providerSpecific: {
                        items: {
                          properties: {
                            name: {
                              type: "string",
                            },
                            value: {
                              type: "string",
                            },
                          },
                          type: "object",
                        },
                        type: "array",
                      },
                      recordTTL: {
                        format: "int64",
                        type: "integer",
                      },
                      recordType: {
                        type: "string",
                      },
                      targets: {
                        items: {
                          type: "string",
                        },
                        type: "array",
                      },
                    },
                    type: "object",
                  },
                  type: "array",
                },
              },
              type: "object",
            },
            status+: {
              properties+: {
                observedGeneration: {
                  format: "int64",
                  type: "integer",
                },
              },
              type: "object",
            },
          },
        },
      },
    },
  },

  clusterRole: kube.ClusterRole($.p + "external-dns") {
    rules: [
      {
        apiGroups: [""],
        resources: ["services", "pods", "nodes"],
        verbs: ["get", "watch", "list"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        verbs: ["get", "watch", "list"],
      },
      {
        apiGroups: ["networking.k8s.io"],
        resources: ["ingresses", "gateways"],
        verbs: ["get", "watch", "list"],
      },
      {
        apiGroups: ["externaldns.k8s.io"],
        resources: ["dnsendpoints"],
        verbs: ["get", "watch", "list"],
      },
      {
        apiGroups: ["externaldns.k8s.io"],
        resources: ["dnsendpoints/status"],
        verbs: ["update"],
      },
    ],
  },

  clusterRoleBinding: kube.ClusterRoleBinding($.p + "external-dns-viewer") {
    roleRef_: $.clusterRole,
    subjects_+: [$.sa],
  },

  sa: kube.ServiceAccount($.p + "external-dns") + $.metadata {
  },

  deploy: kube.Deployment($.p + "external-dns") + $.metadata {
    local this = self,
    ownerId:: error "ownerId is required",
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "7979",
            "prometheus.io/path": "/metrics",
          },
        },
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            edns: kube.Container("external-dns") {
              image: EXTERNAL_DNS_IMAGE,
              args_+: {
                sources_:: ["service", "ingress"],
                registry: "txt",
                "txt-prefix": "_externaldns.",
                "txt-owner-id": this.ownerId,
                "domain-filter": this.ownerId,
                "log-level": "warning",
              },
              args+: ["--source=%s" % s for s in self.args_.sources_],
              ports_+: {
                metrics: {containerPort: 7979},
              },
              readinessProbe: {
                httpGet: {path: "/healthz", port: "metrics"},
              },
              livenessProbe: self.readinessProbe,
            },
          },
        },
      },
    },
  },
}
