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
