local spec = import 'spec-kubeapi.jsonnet';

// Get rid of \n and duplicated whitespaces
local cleanupWhiteSpace(str) = (
  std.join(' ', [
    x
    for x in std.split(std.strReplace(str, '\n', ' '), ' ')
    if x != ''
  ])
);
local rules = [
  spec.metrics[m_key].rules[r_key]
  for m_key in std.objectFields(spec.metrics)
  for r_key in std.objectFields(spec.metrics[m_key].rules)
];

{
  // Emited `rules` as needed by prometheus recording_rules entries
  rules:: [
    rule {
      expr: cleanupWhiteSpace(rule.expr),
    }
    for rule in rules
  ],
  // See https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/
  groups: [
    {
      name: '%s_rules' % spec.name,
      rules: $.rules,
    },
  ],
}
