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

local trim = function(str) (
  if std.startsWith(str, " ") || std.startsWith(str, "\n") then
  trim(std.substr(str, 1, std.length(str) - 1))
  else if std.endsWith(str, " ") || std.endsWith(str, "\n") then
  trim(std.substr(str, 0, std.length(str) - 1))
  else
    str
);

local VERSION = trim(importstr "../VERSION");

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  // This is intended as a publicly available place to see the details
  // of the BKPR install.  If you ever want to know which version of
  // BKPR is currently installed, this is the place you should look.
  config: kube.ConfigMap("release") + $.metadata {
    data+: {
      release: VERSION,
      // There may be additional fields here in future
    },
  },

  readerRole: kube.Role($.p + "release-reader") + $.metadata {
    rules: [
      {
        apiGroups: [""],
        resources: ["configmap"],
        resourceNames: [$.config.metadata.name],
        verbs: ["get", "list", "watch"],
      },
    ],
  },

  readerRoleBinding: kube.RoleBinding($.p + "release-read-public") + $.metadata {
    roleRef_: $.readerRole,
    subjects: [{
      kind: "Group",
      name: "system:authenticated",
      apiGroup: "rbac.authorization.k8s.io",
    }],
  },
}
