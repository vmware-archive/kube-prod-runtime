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
local CERT_MANAGER_IMAGE = (import "images.json")["cert-manager"];

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },
  letsencrypt_contact_email:: error "Letsencrypt contact e-mail is undefined",

  // Letsencrypt environments
  letsencrypt_environments:: {
    "prod": $.letsencryptProd.metadata.name,
    "staging": $.letsencryptStaging.metadata.name,
  },
  // Letsencrypt environment (defaults to the production one)
  letsencrypt_environment:: "prod",

  Issuer(name):: kube._Object("certmanager.k8s.io/v1alpha1", "Issuer", name) {
  },

  ClusterIssuer(name):: kube._Object("certmanager.k8s.io/v1alpha1", "ClusterIssuer", name) {
  },

  certCRD: kube.CustomResourceDefinition("certmanager.k8s.io", "v1alpha1", "Certificate") {
    metadata+: {
      labels+: {
        "controller-tools.k8s.io": "1.0",
      },
    },
    spec+: {
      additionalPrinterColumns+: [
        {
          JSONPath: ".status.conditions[?(@.type==\"Ready\")].status",
          name: "Ready",
          type: "string",
        },
        {
          JSONPath: ".spec.secretName",
          name: "Secret",
          type: "string",
        },
        {
          JSONPath: ".spec.issuerRef.name",
          name: "Issuer",
          priority: 1,
          type: "string",
        },
        {
          JSONPath: ".status.conditions[?(@.type==\"Ready\")].message",
          name: "Status",
          priority: 1,
          type: "string",
        },
        {
          description: "CreationTimestamp is a timestamp representing the server time when this object was created. It is not guaranteed to be set in happens-before order across separate operations. Clients may not set this value. It is represented in RFC3339 form and is in UTC.",
          JSONPath: ".metadata.creationTimestamp",
          name: "Age",
          type: "date",
        },
      ],
      names+: {
        shortNames+: ["cert", "certs"],
      },
    },
  },

  issuerCRD: kube.CustomResourceDefinition("certmanager.k8s.io", "v1alpha1", "Issuer") {
    metadata+: {
      labels+: {
        "controller-tools.k8s.io": "1.0",
      },
    },
  },

  orderCRD: kube.CustomResourceDefinition("certmanager.k8s.io", "v1alpha1", "Order") {
    metadata+: {
      labels+: {
        "controller-tools.k8s.io": "1.0",
      },
    },
    spec+: {
      additionalPrinterColumns+: [
        {
          JSONPath: ".status.state",
          name: "State",
          type: "string",
        },
        {
          JSONPath: ".spec.issuerRef.name",
          name: "Issuer",
          priority: 1,
          type: "string",
        },
        {
          JSONPath: ".status.reason",
          name: "Reason",
          priority: 1,
          type: "string",
        },
        {
          description: "CreationTimestamp is a timestamp representing the server time when this object was created. It is not guaranteed to be set in happens-before order across separate operations. Clients may not set this value. It is represented in RFC3339 form and is in UTC.",
          JSONPath: ".metadata.creationTimestamp",
          name: "Age",
          type: "date",
        },
      ],
    },
  },

  challengeCRD: kube.CustomResourceDefinition("certmanager.k8s.io", "v1alpha1", "Challenge") {
    metadata+: {
      labels+: {
        "controller-tools.k8s.io": "1.0",
      },
    },
    spec+: {
      additionalPrinterColumns+: [
        {
          JSONPath: ".status.state",
          name: "State",
          type: "string",
        },
        {
          JSONPath: ".spec.dnsName",
          name: "Domain",
          type: "string",
        },
        {
          JSONPath: ".status.reason",
          name: "Reason",
          priority: 1,
          type: "string",
        },
        {
          description: "CreationTimestamp is a timestamp representing the server time when this object was created. It is not guaranteed to be set in happens-before order across separate operations. Clients may not set this value. It is represented in RFC3339 form and is in UTC.",
          JSONPath: ".metadata.creationTimestamp",
          name: "Age",
          type: "date",
        },
      ],
    }
  },

  clusterissuerCRD: kube.CustomResourceDefinition("certmanager.k8s.io", "v1alpha1", "ClusterIssuer") {
    metadata+: {
      labels+: {
        "controller-tools.k8s.io": "1.0",
      },
    },
    spec+: {
      scope: "Cluster",
    },
  },

  sa: kube.ServiceAccount($.p + "cert-manager") + $.metadata {
  },

  clusterRole: kube.ClusterRole($.p + "cert-manager") {
    rules: [
      {
        apiGroups: ["certmanager.k8s.io"],
        resources: ["certificates", "certificates/finalizers", "issuers", "clusterissuers", "orders", "orders/finalizers", "challenges"],
        // FIXME: audit - the helm chart just has "*"
        verbs: ["get", "list", "watch", "create", "patch", "update", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["secrets", "configmaps", "services", "pods"],
        // FIXME: audit - the helm chart just has "*"
        verbs: ["get", "list", "watch", "create", "patch", "update", "delete"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        // FIXME: audit - the helm chart just has "*"
        verbs: ["get", "list", "watch", "create", "patch", "update", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch", "update"],
      },
    ],
  },

  clusterRoleBinding: kube.ClusterRoleBinding($.p+"cert-manager") {
    roleRef_: $.clusterRole,
    subjects_+: [$.sa],
  },

  deploy: kube.Deployment($.p+"cert-manager") + $.metadata {
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "9402",
            "prometheus.io/path": "/metrics",
          },
        },
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            default: kube.Container("cert-manager") {
              image: CERT_MANAGER_IMAGE,
              args_+: {
                "cluster-resource-namespace": "$(POD_NAMESPACE)",
                "leader-election-namespace": "$(POD_NAMESPACE)",
                "default-issuer-name": $.letsencrypt_environments[$.letsencrypt_environment],
                "default-issuer-kind": "ClusterIssuer",
              },
              env_+: {
                POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              ports_+: {
                prometheus: {containerPort: 9402},
              },
              resources: {
                requests: {cpu: "10m", memory: "32Mi"},
              },
            },
          },
        },
      },
    },
  },

  letsencryptStaging: $.ClusterIssuer($.p+"letsencrypt-staging") {
    local this = self,
    spec+: {
      acme+: {
        server: "https://acme-staging-v02.api.letsencrypt.org/directory",
        email: $.letsencrypt_contact_email,
        privateKeySecretRef: {name: this.metadata.name},
        http01: {},
      },
    },
  },

  letsencryptProd: $.letsencryptStaging {
    metadata+: {name: $.p+"letsencrypt-prod"},
    spec+: {
      acme+: {
        server: "https://acme-v02.api.letsencrypt.org/directory",
      },
    },
  },
}
