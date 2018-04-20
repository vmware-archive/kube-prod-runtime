// Run fluentd-es-config/import-from-upstream.py to update below files
//
// As computed imports are not supported in jsonnet, need to manually
// add them one-by-one
//
{
  "containers.input.conf": (importstr "fluentd-es-config/containers.input.conf"),
  "forward.input.conf": (importstr "fluentd-es-config/forward.input.conf"),
  "monitoring.conf": (importstr "fluentd-es-config/monitoring.conf"),
  "output.conf": (importstr "fluentd-es-config/output.conf"),
  "system.conf": (importstr "fluentd-es-config/system.conf"),
  "system.input.conf": (importstr "fluentd-es-config/system.input.conf"),
}
