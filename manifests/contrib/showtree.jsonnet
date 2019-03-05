// Simple tool to show BKPR jsonnet objects -> Kubernetes objects tree
// useful to find out where to override wanted fields
// Run as:
//   jsonnet showtree.jsonnet
//   jsonnet showtree.jsonnet | sed -e '1d;$d' -e 's/[",:]//g' | column -t
local helpers = (import 'helpers.jsonnet');

// Need to "fuse" kubecfg.manifestYaml() calls as it's kubecfg internal,
// unsupported by jsonnet
local voidKubecfgInternals(obj) = (
  obj
  + helpers.setAtPath('grafana.datasources.data', { 'bkpr.yml': '' })
  + helpers.setAtPath('prometheus.rules', {})
  + helpers.setAtPath('prometheus.prometheus.config.data', { 'prometheus.yml': '' })
  + helpers.setAtPath('prometheus.alertmanager.config.data', { 'config.yml': '' })
);

// Just picking up one of the supported platforms, to get a full
// kubeprod treeish object
local kubeprod = voidKubecfgInternals(import '../tests/gke.jsonnet');

local formatKube(k, obj) = (
  if std.objectHas(obj.metadata, 'namespace') then
    { [k]: '%s %s -n %s' % [obj.kind, obj.metadata.name, obj.metadata.namespace] }
  else
    { [k]: '%s %s' % [obj.kind, obj.metadata.name] }
);

// Build main tree: jsonnet key -> formatted Kubernetes object
local show_tree(obj) = (
  local tree(key, x) = (
    if std.objectHas(x, 'apiVersion') && std.objectHas(x, 'kind') then
      formatKube(key, x)
    else
      [tree(key + '.' + k, x[k]) for k in std.objectFields(x)]
  );
  tree('', obj)
);

// Flatten into a single object
local flatten(obj) = (
  std.foldl(
    function(x, y) (
      if std.type(y) == 'object' then
        x + y
      else
        x + flatten(y)
    ),
    obj,
    {}
  )
);

flatten(show_tree(kubeprod))
