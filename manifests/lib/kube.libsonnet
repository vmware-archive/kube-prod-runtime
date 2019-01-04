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

// Generic library of Kubernetes objects
// TODO: Expand this to include all API objects.
//
// Should probably fill out all the defaults here too, so jsonnet can
// reference them.  In addition, jsonnet validation is more useful
// (client-side, and gives better line information).

{
  // Returns array of values from given object.  Does not include hidden fields.
  objectValues(o):: [o[field] for field in std.objectFields(o)],

  // Returns array of [key, value] pairs from given object.  Does not include hidden fields.
  objectItems(o):: [[k, o[k]] for k in std.objectFields(o)],

  // Replace all occurrences of `_` with `-`.
  hyphenate(s):: std.join("-", std.split(s, "_")),

  // Convert an octal (as a string) to number,
  parseOctal(s):: (
    local len = std.length(s);
    local leading = std.substr(s, 0, len-1);
    local last = std.substr(s, len-1, 1);
    std.parseInt(last) + (if len > 1 then 8 * $.parseOctal(leading) else 0)
  ),

  // Convert {foo: {a: b}} to [{name: foo, a: b}]
  mapToNamedList(o):: [{ name: $.hyphenate(n) } + o[n] for n in std.objectFields(o)],

  // Convert from SI unit suffixes to regular number
  siToNum(n):: (
    local convert =
      if std.endsWith(n, "m") then [1, 0.001]
      else if std.endsWith(n, "K") then [1, 1e3]
      else if std.endsWith(n, "M") then [1, 1e6]
      else if std.endsWith(n, "G") then [1, 1e9]
      else if std.endsWith(n, "T") then [1, 1e12]
      else if std.endsWith(n, "P") then [1, 1e15]
      else if std.endsWith(n, "E") then [1, 1e18]
      else if std.endsWith(n, "Ki") then [2, std.pow(2, 10)]
      else if std.endsWith(n, "Mi") then [2, std.pow(2, 20)]
      else if std.endsWith(n, "Gi") then [2, std.pow(2, 30)]
      else if std.endsWith(n, "Ti") then [2, std.pow(2, 40)]
      else if std.endsWith(n, "Pi") then [2, std.pow(2, 50)]
      else if std.endsWith(n, "Ei") then [2, std.pow(2, 60)]
      else error "Unknown numerical suffix in " + n;
    local n_len = std.length(n);
    std.parseInt(std.substr(n, 0, n_len - convert[0])) * convert[1]
  ),

  local remap(v, start, end, newstart) =
    if v >= start && v <= end then v - start + newstart else v,
  local remapChar(c, start, end, newstart) =
    std.char(remap(
      std.codepoint(c), std.codepoint(start), std.codepoint(end), std.codepoint(newstart))),
  toLower(s):: (
    std.join("", [remapChar(c, "A", "Z", "a") for c in std.stringChars(s)])
  ),
  toUpper(s):: (
    std.join("", [remapChar(c, "a", "z", "A") for c in std.stringChars(s)])
  ),

  _Object(apiVersion, kind, name):: {
    local this = self,
    apiVersion: apiVersion,
    kind: kind,
    metadata: {
      name: name,
      labels: { name: std.join("-", std.split(this.metadata.name, ":")) },
    },
  },

  List(): {
    apiVersion: "v1",
    kind: "List",
    items_:: {},
    items: $.objectValues(self.items_),
  },

  Namespace(name): $._Object("v1", "Namespace", name) {
  },

  Endpoints(name): $._Object("v1", "Endpoints", name) {
    Ip(addr):: { ip: addr },
    Port(p):: { port: p },

    subsets: [],
  },

  Service(name): $._Object("v1", "Service", name) {
    local service = self,

    target_pod:: error "service target_pod required",
    port:: self.target_pod.spec.containers[0].ports[0].containerPort,

    // Helpers that format host:port in various ways
    host:: "%s.%s.svc" % [self.metadata.name, self.metadata.namespace],
    host_colon_port:: "%s:%s" % [self.host, self.spec.ports[0].port],
    http_url:: "http://%s/" % self.host_colon_port,
    proxy_urlpath:: "/api/v1/proxy/namespaces/%s/services/%s/" % [
      self.metadata.namespace, self.metadata.name,
    ],
    // Useful in Ingress rules
    name_port:: {
      serviceName: service.metadata.name,
      servicePort: service.spec.ports[0].port,
    },

    spec: {
      selector: service.target_pod.metadata.labels,
      ports: [
        {
          port: service.port,
          name: service.target_pod.spec.containers[0].ports[0].name,
          targetPort: service.target_pod.spec.containers[0].ports[0].containerPort,
        },
      ],
      type: "ClusterIP",
    },
  },

  PersistentVolume(name): $._Object("v1", "PersistentVolume", name) {
    spec: {},
  },

  // TODO: This is a terrible name
  PersistentVolumeClaimVolume(pvc): {
    persistentVolumeClaim: { claimName: pvc.metadata.name },
  },

  StorageClass(name): $._Object("storage.k8s.io/v1beta1", "StorageClass", name) {
    provisioner: error "provisioner required",
  },

  PersistentVolumeClaim(name): $._Object("v1", "PersistentVolumeClaim", name) {
    local pvc = self,

    storageClass:: null,
    storage:: error "storage required",

    metadata+: if pvc.storageClass != null then {
      annotations+: {
        "volume.beta.kubernetes.io/storage-class": pvc.storageClass,
      },
    } else {},

    spec: {
      resources: {
        requests: {
          storage: pvc.storage,
        },
      },
      accessModes: ["ReadWriteOnce"],
    },
  },

  Container(name): {
    name: name,
    image: error "container image value required",
    imagePullPolicy: if std.endsWith(self.image, ":latest") then "Always" else "IfNotPresent",

    envList(map):: [
      if std.type(map[x]) == "object" then { name: x, valueFrom: map[x] } else { name: x, value: std.toString(map[x]) }
      for x in std.objectFields(map)],

    env_:: {},
    env: self.envList(self.env_),

    args_:: {},
    args: ["--%s=%s" % kv for kv in $.objectItems(self.args_)],

    ports_:: {},
    ports: $.mapToNamedList(self.ports_),

    volumeMounts_:: {},
    volumeMounts: $.mapToNamedList(self.volumeMounts_),

    stdin: false,
    tty: false,
    assert !self.tty || self.stdin : "tty=true requires stdin=true",
  },

  PodDisruptionBudget(name): $._Object("policy/v1beta1", "PodDisruptionBudget", name) {
    local this = self,
    target_pod:: error "target_pod required",
    spec: {
      assert std.objectHas(self, "minAvailable") || std.objectHas(self, "maxUnavailable") : "exactly one of minAvailable/maxUnavailable required",
      selector: {
        matchLabels: this.target_pod.metadata.labels,
      },
    },
  },

  Pod(name): $._Object("v1", "Pod", name) {
    spec: $.PodSpec,
  },

  PodSpec: {
    // The 'first' container is used in various defaults in k8s.
    local container_names = std.objectFields(self.containers_),
    default_container:: if std.length(container_names) > 1 then "default" else container_names[0],
    containers_:: {},

    local container_names_ordered = [self.default_container] + [n for n in container_names if n != self.default_container],
    containers: [{ name: $.hyphenate(name) } + self.containers_[name] for name in container_names_ordered if self.containers_[name] != null],

    initContainers_:: {},
    initContainers: [{name: $.hyphenate(name) } + self.initContainers_[name] for name in std.objectFields(self.initContainers_) if self.initContainers_[name] != null],

    volumes_:: {},
    volumes: $.mapToNamedList(self.volumes_),

    imagePullSecrets: [],

    terminationGracePeriodSeconds: 30,

    assert std.length(self.containers) > 0 : "must have at least one container",
  },

  EmptyDirVolume(): {
    emptyDir: {},
  },

  HostPathVolume(path, type=""): {
    hostPath: { path: path, type: type },
  },

  GitRepoVolume(repository, revision): {
    gitRepo: {
      repository: repository,

      // "master" is possible, but should be avoided for production
      revision: revision,
    },
  },

  SecretVolume(secret): {
    secret: { secretName: secret.metadata.name },
  },

  ConfigMapVolume(configmap): {
    configMap: { name: configmap.metadata.name },
  },

  ConfigMap(name): $._Object("v1", "ConfigMap", name) {
    data: {},

    // I keep thinking data values can be any JSON type.  This check
    // will remind me that they must be strings :(
    local nonstrings = [k for k in std.objectFields(self.data)
                        if std.type(self.data[k]) != "string"],
    assert std.length(nonstrings) == 0 : "data contains non-string values: %s" % [nonstrings],
  },

  // subtype of EnvVarSource
  ConfigMapRef(configmap, key): {
    assert std.objectHas(configmap.data, key) : "%s not in configmap.data" % [key],
    configMapKeyRef: {
      name: configmap.metadata.name,
      key: key,
    },
  },

  Secret(name): $._Object("v1", "Secret", name) {
    local secret = self,

    type: "Opaque",
    data_:: {},
    data: { [k]: std.base64(secret.data_[k]) for k in std.objectFields(secret.data_) },
  },

  // subtype of EnvVarSource
  SecretKeyRef(secret, key): {
    assert std.objectHas(secret.data, key) : "%s not in secret.data" % [key],
    secretKeyRef: {
      name: secret.metadata.name,
      key: key,
    },
  },

  // subtype of EnvVarSource
  FieldRef(key): {
    fieldRef: {
      apiVersion: "v1",
      fieldPath: key,
    },
  },

  // subtype of EnvVarSource
  ResourceFieldRef(key, divisor="1"): {
    resourceFieldRef: {
      resource: key,
      divisor: std.toString(divisor),
    },
  },

  Deployment(name): $._Object("apps/v1beta1", "Deployment", name) {
    local deployment = self,

    spec: {
      template: {
        spec: $.PodSpec,
        metadata: {
          labels: deployment.metadata.labels,
        },
      },

      selector: {
        matchLabels: deployment.spec.template.metadata.labels,
      },

      strategy: {
        type: "RollingUpdate",

        local pvcs = [v for v in deployment.spec.template.spec.volumes
                      if std.objectHas(v, "persistentVolumeClaim")],
        local is_stateless = std.length(pvcs) == 0,

        // Apps trying to maintain a majority quorum or similar will
        // want to tune these carefully.
        // NB: Upstream default is surge=1 unavail=1
        rollingUpdate: if is_stateless then {
          maxSurge: "25%",  // rounds up
          maxUnavailable: "25%",  // rounds down
        } else {
          // Poor-man's StatelessSet.  Useful mostly with replicas=1.
          maxSurge: 0,
          maxUnavailable: 1,
        },
      },

      // NB: Upstream default is 0
      minReadySeconds: 30,

      replicas: 1,
      assert self.replicas >= 1,
    },
  },

  CrossVersionObjectReference(target): {
    apiVersion: target.apiVersion,
    kind: target.kind,
    name: target.metadata.name,
  },

  HorizontalPodAutoscaler(name): $._Object("autoscaling/v1", "HorizontalPodAutoscaler", name) {
    local hpa = self,

    target:: error "target required",

    spec: {
      scaleTargetRef: $.CrossVersionObjectReference(hpa.target),

      minReplicas: hpa.target.spec.replicas,
      maxReplicas: error "maxReplicas required",

      assert self.maxReplicas >= self.minReplicas,
    },
  },

  StatefulSet(name): $._Object("apps/v1beta2", "StatefulSet", name) {
    local sset = self,

    spec: {
      serviceName: name,

      updateStrategy: {
        type: "RollingUpdate",
      },

      template: {
        spec: $.PodSpec,
        metadata: {
          labels: sset.metadata.labels,
        },
      },

      selector: {
        matchLabels: sset.spec.template.metadata.labels,
      },

      volumeClaimTemplates_:: {},
      volumeClaimTemplates: [
        // StatefulSet is overly fussy about "changes" (even when
        // they're no-ops).
        // In particular annotations={} is apparently a "change",
        // since the comparison is ignorant of defaults.
        std.prune($.PersistentVolumeClaim($.hyphenate(kv[0])) + {apiVersion:: null, kind:: null} + kv[1])
        for kv in $.objectItems(self.volumeClaimTemplates_)],

      replicas: 1,
      assert self.replicas >= 1,
    },
  },

  Job(name): $._Object("batch/v1", "Job", name) {
    local job = self,

    spec: {
      template: {
        spec: $.PodSpec {
          restartPolicy: "OnFailure",
        },
        metadata: {
          labels: job.metadata.labels,
        },
      },

      completions: 1,
      parallelism: 1,
    },
  },

  DaemonSet(name): $._Object("extensions/v1beta1", "DaemonSet", name) {
    local ds = self,
    spec: {
      updateStrategy: {
        type: "RollingUpdate",
        rollingUpdate: {
          maxUnavailable: 1,
        },
      },
      template: {
        metadata: {
          labels: ds.metadata.labels,
        },
        spec: $.PodSpec,
      },

      selector: {
        matchLabels: ds.spec.template.metadata.labels,
      },
    },
  },

  Ingress(name): $._Object("extensions/v1beta1", "Ingress", name) {
    spec: {},

    local rel_paths = [
      p.path
      for r in self.spec.rules
      for p in r.http.paths
      if !std.startsWith(p.path, "/")
      ],
    assert std.length(rel_paths) == 0 : "paths must be absolute: " + rel_paths,
  },

  ThirdPartyResource(name): $._Object("extensions/v1beta1", "ThirdPartyResource", name) {
    versions_:: [],
    versions: [{ name: n } for n in self.versions_],
  },

  CustomResourceDefinition(group, version, kind): {
    local this = self,
    apiVersion: "apiextensions.k8s.io/v1beta1",
    kind: "CustomResourceDefinition",
    metadata+: {
      name: this.spec.names.plural + "." + this.spec.group,
    },
    spec: {
      scope: "Namespaced",
      group: group,
      version: version,
      names: {
        kind: kind,
        singular: $.toLower(self.kind),
        plural: self.singular + "s",
        listKind: self.kind + "List",
      },
    },
  },

  ServiceAccount(name): $._Object("v1", "ServiceAccount", name) {
  },

  Role(name): $._Object("rbac.authorization.k8s.io/v1beta1", "Role", name) {
    rules: [],
  },

  ClusterRole(name): $.Role(name) {
    kind: "ClusterRole",
  },

  Group(name): {
    kind: "Group",
    name: name,
    apiGroup: "rbac.authorization.k8s.io",
  },

  RoleBinding(name): $._Object("rbac.authorization.k8s.io/v1beta1", "RoleBinding", name) {
    local rb = self,

    subjects_:: [],
    subjects: [{
      kind: o.kind,
      namespace: o.metadata.namespace,
      name: o.metadata.name,
    } for o in self.subjects_],

    roleRef_:: error "roleRef is required",
    roleRef: {
      apiGroup: "rbac.authorization.k8s.io",
      kind: rb.roleRef_.kind,
      name: rb.roleRef_.metadata.name,
    },
  },

  ClusterRoleBinding(name): $.RoleBinding(name) {
    kind: "ClusterRoleBinding",
  },

  NetworkPolicy(name): $._Object("networking.k8s.io/v1", "NetworkPolicy", name) {
    local this = self,
    target:: error "target is required",
    spec+: {
      podSelector: {matchLabels: this.target.metadata.labels},
    },
  },

  PodZoneAntiAffinityAnnotation(pod): {
    podAntiAffinity: {
      preferredDuringSchedulingIgnoredDuringExecution: [
        {
          weight: 50,
          podAffinityTerm: {
            labelSelector: { matchLabels: pod.metadata.labels },
            topologyKey: "failure-domain.beta.kubernetes.io/zone",
          },
        },
        {
          weight: 100,
          podAffinityTerm: {
            labelSelector: { matchLabels: pod.metadata.labels },
            topologyKey: "kubernetes.io/hostname",
          },
        },
      ],
    },
  },
}
