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
local bkpr_rel = import "bkpr-release.jsonnet";

local arch = "amd64";

{
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  serviceAccount: kube.ServiceAccount("heapster") + $.metadata {
  },

  clusterRoleBinding: kube.ClusterRoleBinding("heapster-binding") {
    roleRef: {
      apiGroup: "rbac.authorization.k8s.io",
      kind: "ClusterRole",
      name: "system:heapster",
    },
    subjects_: [$.serviceAccount],
  },

  nannyRole: kube.Role("pod-nanny") + $.metadata {
    metadata+: {
      name: "system:pod-nanny"
    },
    rules: [
      {
        apiGroups: [""],
        resources: ["pods"],
        verbs: ["get"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["deployments"],
        verbs: ["get", "update"],
      },
    ],
  },

  roleBinding: kube.RoleBinding("heapster-binding") + $.metadata {
    roleRef_: $.nannyRole,
    subjects_: [$.serviceAccount],
  },

  service: kube.Service("heapster") + $.metadata {
    target_pod: $.deployment.spec.template,
    port: 80,
  },

  deployment: kube.Deployment("heapster") + $.metadata {
    local this = self,
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            "scheduler.alpha.kubernetes.io/critical-pod": "",
          },
        },
        spec+: {
          local this_containers = self.containers_,
          serviceAccountName: $.serviceAccount.metadata.name,
          nodeSelector+: {"beta.kubernetes.io/arch": arch},
          containers_+: {
            default: kube.Container("heapster") {
              image: bkpr_rel.heapster__arch.image % {arch: arch},
              command: ["/heapster"],
              args_+: {
                source: "kubernetes.summary_api:''",
              },
              ports_+: {
                default: { containerPort: 8082 },
              },
              livenessProbe: {
                httpGet: { path: "/healthz", port: 8082, scheme: "HTTP" },
                initialDelaySeconds: 180,
                timeoutSeconds: 5,
              },
            },
            nanny: kube.Container("heapster-nanny") {
              image: bkpr_rel.addon_resizer__arch.image % {arch: arch},
              command: ["/pod_nanny"],
              args_+: {
                cpu: "80m",
                "extra-cpu": "0.5m",
                memory: "140Mi",
                "extra-memory": "4Mi",
                deployment: this.metadata.name,
                container: this_containers.default.name,
                "poll-period": 300000,
              },
              resources: {
                limits: { cpu: "50m", memory: "90Mi" },
                requests: self.limits,
              },
              env_+: {
                MY_POD_NAME: kube.FieldRef("metadata.name"),
                MY_POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
            },
          },
        },
      },
    },
  },
}
