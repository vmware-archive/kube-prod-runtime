/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018 Bitnami
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

// See https://github.com/GoogleCloudPlatform/k8s-service-catalog

{
  p:: "",

  oauthSecret: kube.Secret($.p+"google-oauth") {
    local this = self,
    data_+: {
      key: null, // long-lived service account json key goes here
      scopes: '["https://www.googleapis.com/auth/cloud-platform"]',
      secretName: "gcp-svc-account-secret",
      secretNamespace: this.metadata.namespace,
    },
  },

  sa: kube.ServiceAccount($.p+"google-oauth"),

  oauthClusterRole: kube.ClusterRole($.p+"google-oauth") {
    // TODO: ouch.  This should be significantly narrower scope.
    rules: [
      {
        apiGroups: [""],
        resources: ["secrets"],
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["namespaces"],
        verbs: ["get", "list", "watch"],
      },
    ],
  },

  oauthClusterRoleBinding: kube.ClusterRoleBinding($.p+"google-oauth") {
    roleRef_: $.oauthClusterRole,
    subjects_+: [$.sa],
  },

  deploy: kube.Deployment($.p+"google-oauth") {
    spec+: {
      template+: {
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            oauth: kube.Container("catalog-oauth") {
              image: "gcr.io/gcp-services/catalog-oauth:latest",  // FIXME: release?
              args_+: {
                n: "$(POD_NAMESPACE)",
                v: 6,
                alsologtostderr: true,
              },
              env_+: {
                POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              ports_+: {
                default: {containerPort: 8443},
              },
              resources+: {
                requests: {cpu: "100m", memory: "20Mi"},
                limits: {cpu: "100m", memory: "30Mi"},
              },
            },
          },
        },
      },
    },
  },
}
