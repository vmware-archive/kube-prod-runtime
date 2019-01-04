#!/usr/bin/env python

# Bitnami Kubernetes Production Runtime - A collection of services that makes it
# easy to run production workloads in Kubernetes.
#
# Copyright 2018-2019 Bitnami
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Save *.conf files needed for fluentd-es log pre-processing from upstream
# yaml-s

import os
import yaml
import requests

r = requests.get("https://raw.githubusercontent.com/kubernetes/kubernetes/"
                 "master/cluster/addons/fluentd-elasticsearch/"
                 "fluentd-es-configmap.yaml")
DIR = os.path.dirname(__file__)

for fname, content in yaml.safe_load(r.text)['data'].items():
    fname = os.path.join(DIR, fname)
    print("Saving to " + fname)
    with open(fname, "w") as f:
        f.write(content)
        f.write("\n")  # Add trailing newline
