local spec = import 'spec-kubeapi.jsonnet';

// Get rid of \n and duplicated whitespaces
local cleanupWhiteSpace(str) = (
  std.join(' ', [
    x
    for x in std.split(std.strReplace(str, '\n', ' '), ' ')
    if x != ''
  ])
);
local checks = [
  spec.metrics[m_key].alerts[a_key]
  for m_key in std.objectFields(spec.metrics)
  for a_key in std.objectFields(spec.metrics[m_key].alerts)
];

{
  // Emited `rules` as needed by prometheus alert entries
  rules:: [
    {
      alert: check.name,
      expr: cleanupWhiteSpace(check.expr),
      'for': check['for'],
      labels+: check.labels,
      annotations+: check.annotations,
    }
    for check in checks
  ],
  // See https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/
  groups: [
    {
      name: '%s_alerts' % spec.name,
      rules: $.rules,
    },
  ],
}
