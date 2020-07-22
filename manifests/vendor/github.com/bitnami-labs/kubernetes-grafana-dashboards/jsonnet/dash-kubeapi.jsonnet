local grafana = import 'grafonnet-lib/grafonnet/grafana.libsonnet';
local template = grafana.template;
local row = grafana.row;
local bitgraf = import 'bitnami_grafana.libsonnet';

local spec = (import 'spec-kubeapi.jsonnet');

local rows = [
  {
    local m = spec.metrics[m_key],
    title: m.name,
    panels: [
      m.graphs[g_key]
      for g_key in std.objectFields(m.graphs)
    ],
  }
  for m_key in std.objectFields(spec.metrics)
];

bitgraf.dash.new(spec.grafana.title, tags=spec.grafana.tags)
.addRows([
  row.new(height='250px', title=x.title)
  .addPanels([
    bitgraf.panel.new(p)
    .addTarget(
      bitgraf.prom(p.formula, p.legend)
    )
    for p in x.panels
  ])
  for x in rows
]) {
  local t = spec.grafana.templates_custom,
  templates+: [
    template.custom(x, t[x].values, t[x].default, hide=t[x].hide)
    for x in std.objectFields(t)
  ],
}
