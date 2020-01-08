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

local ELASTICSEARCH_CURATOR_IMAGE = (import "images.json")["elasticsearch-curator"];

local action_file_yml_tmpl = importstr "elasticsearch-config/action_file_yml_tmpl";
local config_yml_tmpl = importstr "elasticsearch-config/config_yml_tmpl";

// Implement elasticsearch-curator as a Kubernetes CronJob
{
  namespace:: "kubeprod",
  name:: "elasticsearch-curator",
  retention:: error "retention must be externally provided ...",
  host:: error "host must be externally provided ...",
  port:: error "port must be externally provided ...",
  schedule:: error "schedule must be externally provided ...",

  elasticsearch_curator_config: kube.ConfigMap($.name) {
    metadata+: {namespace: $.namespace},
    data+: {
      "action_file.yml": std.format(action_file_yml_tmpl, [$.retention]),
      "config.yml": std.format(config_yml_tmpl, [$.host, $.port]),
    },
  },

  elasticsearch_curator_cronjob: kube.CronJob($.name) {
    metadata+: {namespace: $.namespace},
    spec+: {
      schedule: $.schedule,
      jobTemplate+: {
        spec+: {
          template+: {
            spec+: {
              containers_+: {
                curator: kube.Container("curator") {
                  image: ELASTICSEARCH_CURATOR_IMAGE,
                  args: ["--config", "/etc/config/config.yml", "/etc/config/action_file.yml"],
                  volumeMounts_+: {
                    config_vol: {mountPath: "/etc/config", readOnly: true},
                  },
                },
              },
              volumes_+: {config_vol: kube.ConfigMapVolume($.elasticsearch_curator_config)},
            },
          },
        },
      },
    },
  },
}
