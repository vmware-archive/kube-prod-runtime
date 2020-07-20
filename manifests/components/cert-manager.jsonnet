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

local kube = import "../vendor/github.com/bitnami-labs/kube-libsonnet/kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local CERT_MANAGER_IMAGE = (import "images.json")["cert-manager"];
local CERT_MANAGER_ACMESOLVER_IMAGE = (import "images.json")["cert-manager-acmesolver"];

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
    prod: $.letsencryptProd.metadata.name,
    staging: $.letsencryptStaging.metadata.name,
  },
  // Letsencrypt environment (defaults to the production one)
  letsencrypt_environment:: "prod",

  Issuer(name):: kube._Object("cert-manager.io/v1alpha2", "Issuer", name) {
  },

  ClusterIssuer(name):: kube._Object("cert-manager.io/v1alpha2", "ClusterIssuer", name) {
  },

  CRDS: kubecfg.parseYaml(importstr "crds/cert-manager.yaml"),

  sa: kube.ServiceAccount($.p + "cert-manager") + $.metadata,

  certificatesClusterRole: kube.ClusterRole($.p + "cert-manager-certificates") {
    rules: [
      {
        apiGroups: ["cert-manager.io"],
        resources: ["certificates", "certificates/status", "certificaterequests", "certificaterequests/status"],
        verbs: ["update"],
      },
      {
        apiGroups: ["cert-manager.io"],
        resources: ["certificates", "certificaterequests", "clusterissuers", "issuers"],
        verbs: ["get", "list", "watch"],
      },
      // We require these rules to support users with the OwnerReferencesPermissionEnforcement
      // admission controller enabled:
      // https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#ownerreferencespermissionenforcement
      {
        apiGroups: ["cert-manager.io"],
        resources: ["certificates/finalizers", "certificaterequests/finalizers"],
        verbs: ["update"],
      },
      {
        apiGroups: ["acme.cert-manager.io"],
        resources: ["orders"],
        verbs: ["create", "delete", "get", "list", "watch"],
      },
      {
        apiGroups: [""],
        resources: ["secrets"],
        verbs: ["get", "list", "watch", "create", "update", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch"],
      },
    ],
  },

  certificatesClusterRoleBinding: kube.ClusterRoleBinding($.p + "cert-manager-certificates") {
    roleRef_: $.certificatesClusterRole,
    subjects_+: [$.sa],
  },

  ingressShimClusterRole: kube.ClusterRole($.p + "cert-manager-ingress-shim") {
    rules: [
      {
        apiGroups: ["cert-manager.io"],
        resources: ["certificates", "certificaterequests"],
        verbs: ["create", "update", "delete"],
      },
      {
        apiGroups: ["cert-manager.io"],
        resources: ["certificates", "certificaterequests", "issuers", "clusterissuers"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        verbs: ["get", "list", "watch"],
      },
      // We require these rules to support users with the OwnerReferencesPermissionEnforcement
      // admission controller enabled:
      // https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#ownerreferencespermissionenforcement
      {
        apiGroups: ["extensions"],
        resources: ["ingresses/finalizers"],
        verbs: ["update"],
      },
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch"],
      },
    ],
  },

  ingressShimClusterRoleBinding: kube.ClusterRoleBinding($.p + "cert-manager-ingress-shim") {
    roleRef_: $.ingressShimClusterRole,
    subjects_+: [$.sa],
  },

  challengesClusterRole: kube.ClusterRole($.p + "cert-manager-challenges") {
    rules: [
      // Use to update challenge resource status
      {
        apiGroups: ["acme.cert-manager.io"],
        resources: ["challenges", "challenges/status"],
        verbs: ["update"],
      },
      // Used to watch challenge resources
      {
        apiGroups: ["acme.cert-manager.io"],
        resources: ["challenges"],
        verbs: ["get", "list", "watch"],
      },
      // Used to watch challenges, issuer and clusterissuer resources
      {
        apiGroups: ["cert-manager.io"],
        resources: ["issuers", "clusterissuers"],
        verbs: ["get", "list", "watch"],
      },
      // Need to be able to retrieve ACME account private key to complete challenges
      {
        apiGroups: [""],
        resources: ["secrets"],
        verbs: ["get", "list", "watch"],
      },
      // Used to create events
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch"],
      },
      // HTTP01 rules
      {
        apiGroups: [""],
        resources: ["pods", "services"],
        verbs: ["get", "list", "watch", "create", "delete"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        verbs: ["get", "list", "watch", "create", "delete", "update"],
      },
      // We require these rules to support users with the OwnerReferencesPermissionEnforcement
      // admission controller enabled:
      // https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#ownerreferencespermissionenforcement
      {
        apiGroups: ["acme.cert-manager.io"],
        resources: ["challenges/finalizers"],
        verbs: ["update"],
      },
      // DNS01 rules (duplicated above)
      {
        apiGroups: [""],
        resources: ["secrets"],
        verbs: ["get", "list", "watch"],
      },
    ],
  },

  challengesClusterRoleBinding: kube.ClusterRoleBinding($.p + "cert-manager-challenges") {
    roleRef_: $.challengesClusterRole,
    subjects_+: [$.sa],
  },

  issuersClusterRole: kube.ClusterRole($.p + "cert-manager-issuers") {
    rules: [
      {
        apiGroups: ["cert-manager.io"],
        resources: ["issuers", "issuers/status"],
        verbs: ["update"],
      },
      {
        apiGroups: ["cert-manager.io"],
        resources: ["issuers"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: [""],
        resources: ["secrets"],
        verbs: ["get", "list", "watch", "create", "update", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch"],
      },
    ],
  },

  issuersClusterRoleBinding: kube.ClusterRoleBinding($.p + "cert-manager-issuers") {
    roleRef_: $.issuersClusterRole,
    subjects_+: [$.sa],
  },

  clusterissuersClusterRole: kube.ClusterRole($.p + "cert-manager-clusterissuers") {
    rules: [
      {
        apiGroups: ["cert-manager.io"],
        resources: ["clusterissuers", "clusterissuers/status"],
        verbs: ["update"],
      },
      {
        apiGroups: ["cert-manager.io"],
        resources: ["clusterissuers"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: [""],
        resources: ["secrets"],
        verbs: ["get", "list", "watch", "create", "update", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch"],
      },
    ],
  },

  clusterissuersClusterRoleBinding: kube.ClusterRoleBinding($.p + "cert-manager-clusterissuers") {
    roleRef_: $.clusterissuersClusterRole,
    subjects_+: [$.sa],
  },

  ordersClusterRole: kube.ClusterRole($.p + "cert-manager-orders") {
    rules: [
      {
        apiGroups: ["acme.cert-manager.io"],
        resources: ["orders", "orders/status"],
        verbs: ["update"],
      },
      {
        apiGroups: ["acme.cert-manager.io"],
        resources: ["orders", "challenges"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: ["cert-manager.io"],
        resources: ["clusterissuers", "issuers"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: ["acme.cert-manager.io"],
        resources: ["challenges"],
        verbs: ["create", "delete"],
      },
      // We require these rules to support users with the OwnerReferencesPermissionEnforcement
      // admission controller enabled:
      // https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#ownerreferencespermissionenforcement
      {
        apiGroups: ["acme.cert-manager.io"],
        resources: ["orders/finalizers"],
        verbs: ["update"],
      },
      {
        apiGroups: [""],
        resources: ["secrets"],
        verbs: ["get", "list", "watch"],
      },
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch"],
      },
    ],
  },

  ordersClusterRoleBinding: kube.ClusterRoleBinding($.p + "cert-manager-orders") {
    roleRef_: $.ordersClusterRole,
    subjects_+: [$.sa],
  },

  editClusterRole: kube.ClusterRole($.p + "cert-manager-edit") {
    rules: [
      {
        apiGroups: ["cert-manager.io"],
        resources: ["certificates", "certificaterequests", "issuers"],
        verbs: ["create", "delete", "deletecollection", "patch", "update"],
      },
    ],
  },

  viewClusterRole: kube.ClusterRole($.p + "cert-manager-view") {
    rules: [
      {
        apiGroups: ["cert-manager.io"],
        resources: ["certificates", "certificaterequests", "issuers"],
        verbs: ["get", "list", "watch"],
      },
    ],
  },

  leaderelectionRole: kube.Role($.p + "cert-manager:leaderelection") + $.metadata {
    rules: [
      {
        apiGroups: [""],
        resources: ["configmaps"],
        verbs: ["get", "create", "update", "patch"],
      },
    ],
  },

  leaderelectionRoleBinding: kube.RoleBinding($.p + "cert-manager:leaderelection") + $.metadata {
    roleRef_: $.leaderelectionRole,
    subjects_+: [$.sa],
  },

  deploy: kube.Deployment($.p + "cert-manager") + $.metadata {
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
                v: "2",
                "acme-http01-solver-image": CERT_MANAGER_ACMESOLVER_IMAGE,
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

  letsencryptStaging: $.ClusterIssuer($.p + "letsencrypt-staging") {
    local this = self,
    spec+: {
      acme+: {
        server: "https://acme-staging-v02.api.letsencrypt.org/directory",
        email: $.letsencrypt_contact_email,
        privateKeySecretRef: {name: this.metadata.name},
        solvers: [{http01: {ingress: {class: "nginx"}}}],
      },
    },
  },

  letsencryptProd: $.letsencryptStaging {
    metadata+: {name: $.p + "letsencrypt-prod"},
    spec+: {
      acme+: {
        server: "https://acme-v02.api.letsencrypt.org/directory",
      },
    },
  },
}
