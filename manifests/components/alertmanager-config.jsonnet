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

// https://prometheus.io/docs/alerting/configuration/
{
  global: {
    resolve_timeout: "5m",
  },

  //templates: []

  route: {
    group_by: ["alertname", "cluster", "service"],

    group_wait: "30s",

    group_interval: "5m",
    repeat_interval: "7d",

    receiver: "email",

    routes: [
    ],
  },

  inhibit_rules: [
    {
      source_match: {severity: "critical"},
      target_match: {severity: "warning"},
      equal: ["alertname", "cluster", "service"],
    },
  ],

  receivers_:: {
    email: {
      //email_configs: [{to: "foo@example.com"}],
    },
  },
  receivers: [{name: k} + self.receivers_[k] for k in std.objectFields(self.receivers_)],
}
