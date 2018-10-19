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

{
  p:: "",

  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    }
  },

  svc: kube.Service($.p+"etcd") + $.metadata {
    target_pod: $.etcd.spec.template,
    port: 2379,
  },

  etcd: kube.StatefulSet($.p+"etcd") + $.metadata {
    spec+: {
      replicas: 3,
      volumeClaimTemplates_+: {
        data: {storage: "10Gi"},
      },
      podManagementPolicy: "Parallel",
      template+: {
        spec+: {
          terminationGracePeriodSeconds: 30,
          containers_+: {
            etcd: kube.Container("etcd") {
              image: "quay.io/coreos/etcd:v3.3.1",
              resources+: {
                requests: {cpu: "100m", memory: "20Mi"},
                limits: {cpu: "100m", memory: "30Mi"},
              },
              env_+: {
                ETCD_DATA_DIR: "/etcd-data",
              },
              command: ["/usr/local/bin/etcd"],
              args_+: {
                "listen-client-urls": "http://0.0.0.0:2379",
                // important: no trailing slash:
                "advertise-client-urls": "http://" + $.svc.host_colon_port,
              },
              ports_+: {
                default: {containerPort: 2379},
              },
              volumeMounts_+: {
                data: {mountPath: "/etcd-data"},
              },
              readinessProbe: {
                httpGet: {port: 2379, path: "/health"},
                failureThreshold: 1,
                initialDelaySeconds: 10,
                periodSeconds: 10,
                successThreshold: 1,
                timeoutSeconds: 2,
              },
              livenessProbe: self.readinessProbe {
                failureThreshold: 3,
              },
            },
          },
        },
      },
    },
  },
}
