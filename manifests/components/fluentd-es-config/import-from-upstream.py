#!/usr/bin/env python
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
