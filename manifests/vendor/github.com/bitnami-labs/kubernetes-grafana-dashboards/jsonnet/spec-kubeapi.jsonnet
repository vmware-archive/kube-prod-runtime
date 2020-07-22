local runbook_url = 'https://engineering-handbook.nami.run/sre/runbooks/kubeapi';
{
  // General settings
  name:: 'kubeapi',
  slo:: {
    target: 0.99,
    error_ratio_threshold: 0.01,
    latency_percentile: 90,
    latency_threshold: 200,
  },
  prometheus:: {
    alerts_common: {
      labels: {
        notify_to: 'slack',
        slack_channel: '#sre-alerts',
        severity: 'critical',
      },
      'for': '5m',
    },
  },
  grafana:: {
    title: 'SLO: Kubernetes API',
    tags: ['k8s', 'api', 'sla'],
    common: {
      extra+: { legend+: { rightSide: true } },
    },
    templates_custom: {
      availability_span: {
        // NOTE: will depend on prometheus retention time
        values: '10m,1h,1d,7d,21d,30d,90d',
        default: '7d',
        hide: '',
      },
      api_percentile: {
        values: '50, 90, 99',
        default: '%s' % [$.slo.latency_percentile],
        hide: '',
      },
      verb_excl: {
        values: $.metrics.kube_api.verb_excl,
        default: $.metrics.kube_api.verb_excl,
        hide: 'variable',
      },
    },
  },
  // Dictionary with metrics, keyed by service.
  // In this particular case: kube_api (api itself), kube_control_mgr, kube_etcd
  // Each metric entry has 3 relevant keys:
  // - graphs: consumed by dash-kubeapi.jsonnet to produce grafana dashboards (.json)
  // - rules: consumed by rules-kubeapi.jsonnet to produce prometheus recorded rules (.rules.yml)
  // - alerts: consumed by alerts-kubeapi.jsonnet to produce prometheus alert rules (.rules.yml)
  //
  // Pseudo convention, re: rules prefixes:
  // 'kubernetes:<...>'  normal recorded rule
  // 'kubernetes::<...>' ditto above, also intended to be federated, matching '.+::.+' regex
  metrics:: {
    kube_api: {
      // General (opinionated) settings for this metric
      local metric = self,

      // We're explicitly excluding these verbs from graphing because they tend to be spiky:
      // - WATCH: API exported metrics show steady 8secs, guess it's so by implementation
      // - CONNECT, PROXY: depend on control-plane -> nodes connectivity
      verb_excl:: 'CONNECT|WATCH|PROXY',
      verb_slos:: 'GET|POST|DELETE|PATCH',
      name:: 'Kube API',
      graphs: {
        // Singlestat showing the service availabilty (%) over selectable $availability_span
        // (grafana template variable)
        aa_availability: $.grafana.common {
          title: 'Availability over $availability_span',
          type: 'singlestat',
          legend: '{{ job }}',
          formula: |||
            sum_over_time(%s[$availability_span]) / sum_over_time(%s[$availability_span])
          ||| % [metric.rules.slo_ok.record, metric.rules.slo_sample.record],
          threshold: '%.2f' % $.slo.target,
          extra: { span: 2, format: 'percentunit', valueFontSize: '80%', legend+: { rightSide: false } },
        },
        // Singlestat showing time budget remaining from the selected $availability_span
        ab_availability: $.grafana.common {
          title: 'Budget remaining from $availability_span',
          type: 'singlestat',
          legend: '{{ job }}',
          // time remaining: (<availability_ratio> - <target>) * <time_period_secs>
          // <time_period_secs> is calculated as:
          //    current time() - timestamp(<any_metric offseted by time_period>)
          formula: |||
            scalar((sum_over_time(%s[$availability_span]) / sum_over_time(%s[$availability_span]) - %s)) * 
              scalar((time() - timestamp(up{job="prometheus"} offset $availability_span)))
          ||| % [
            metric.rules.slo_ok.record,
            metric.rules.slo_sample.record,
            $.slo.target,
          ],
          threshold: '%.2f' % $.slo.target,
          extra: { span: 2, format: 's', decimals: 2, valueFontSize: '80%', legend+: { rightSide: false } },
        },
        // Graph showing fixed short-span service availabilty ([10m])
        ac_availability: $.grafana.common {
          title: 'SLO: Availaibility over 10m',
          legend_rightSide: false,
          legend: '{{ job }}',
          formula: |||
            sum_over_time(%s[10m]) / sum_over_time(%s[10m])
          ||| % [metric.rules.slo_ok.record, metric.rules.slo_sample.record],
          threshold: '%.2f' % $.slo.target,
          extra: { span: 2 },
        },
        // Graph showing 500s except `verb_excl`
        ad_error_ratio: $.grafana.common {
          title: 'API non-200s/total ratio (except %s)' % [metric.verb_excl],
          formula: 'sum by (job, verb, code, instance)(%s{verb!~"%s", code!~"2.."})' % [
            metric.rules.requests_ratiorate_job_verb_code_instance.record,
            metric.verb_excl,
          ],
          legend: '{{ verb }} - {{ code }} - {{ instance }}',
          threshold: $.slo.error_ratio_threshold,
          extra: { span: 6 },
        },
        // Graph showing all requests ratios
        ba_req_ratio: $.grafana.common {
          title: 'API requests ratios',
          formula: metric.rules.requests_ratiorate_job_verb_code.record,
          legend: '{{ verb }} - {{ code }}',
          threshold: 1e9,
        },
        // Graph showing latency except `verb_excl`
        ca_latency: $.grafana.common {
          title: 'API $api_percentile-th latency[ms] by verb (except %s)' % [metric.verb_excl],
          formula: '%s{verb!~"%s"}' % [
            metric.rules.latency_job_verb_instance.record,
            metric.verb_excl,
          ],
          legend: '{{ verb }} - {{ instance }}',
          threshold: $.slo.latency_threshold,
        },
      },
      alerts: {
        // Alert on 500s ratio above chosen `error_ratio_threshold` for `verb_slos`
        error_ratio: $.prometheus.alerts_common {
          local alert = self,
          name: 'KubeAPIErrorRatioHigh',
          expr: 'sum by (instance)(%s{verb=~"%s", code=~"5.."}) > %s' % [
            metric.rules.requests_ratiorate_job_verb_code_instance.record,
            metric.verb_slos,
            $.slo.error_ratio_threshold,
          ],
          annotations: {
            summary: 'Kube API 500s ratio is High',
            description: |||
              Issue: Kube API Error ratio on {{ $labels.instance }} is above %s: {{ $value }}
              Playbook: %s#%s
            ||| % [$.slo.error_ratio_threshold, runbook_url, alert.name],
          },
        },
        // Alert on 500s ratio above chosen `error_ratio_threshold` for `verb_slos`
        latency: $.prometheus.alerts_common {
          local alert = self,
          name: 'KubeAPILatencyHigh',
          expr: 'max by (instance)(%s{verb=~"%s"}) > %s' % [
            metric.rules.latency_job_verb_instance.record,
            metric.verb_slos,
            $.slo.latency_threshold,
          ],
          annotations: {
            summary: 'Kube API Latency is High',
            description: |||
              Issue: Kube API Latency on {{ $labels.instance }} is above %s ms: {{ $value }}
              Playbook: %s#%s
            ||| % [$.slo.latency_threshold, runbook_url, alert.name],
          },
        },
        blackbox: $.prometheus.alerts_common {
          local alert = self,
          name: 'KubeAPIUnHealthy',
          expr: 'probe_success{provider="kubernetes"} == 0',
          annotations: {
            summary: 'Kube API is unhealthy',
            description: |||
              Issue: Kube API is not responding 200s from blackbox.monitoring
              Playbook: %s#%s
            ||| % [runbook_url, alert.name],
          },
        },
      },
      // Recorded rules
      rules: {
        common:: { labels+: { job: 'kubernetes_api_slo' } },
        // ### Rates ###
        // Create several r-rules from rate() over apiserver_request_count,
        // with different label sets

        // Requests rate by all reasonable labels
        requests_rate_job_verb_code_instance: self.common {
          record: 'kubernetes:job_verb_code_instance:apiserver_requests:rate5m',
          expr: 'sum by (job, verb, code, instance)(rate(apiserver_request_count[5m]))',
        },
        // Requests ratio_rate by all reasonable labels
        requests_ratiorate_job_verb_code_instance: self.common {
          record: 'kubernetes:job_verb_code_instance:apiserver_requests:ratio_rate5m',
          expr: '%s / ignoring(verb, code) group_left sum by (job, instance)(%s)' % [
            metric.rules.requests_rate_job_verb_code_instance.record,
            metric.rules.requests_rate_job_verb_code_instance.record,
          ],
        },
        // Requests rate without instance, intended for federation / LT-storage
        requests_rate_job_verb_code: self.common {
          record: 'kubernetes::job_verb_code:apiserver_requests:rate5m',
          expr: 'sum without (instance)(%s)' % [
            metric.rules.requests_rate_job_verb_code_instance.record,
          ],
        },
        // Requests ratio_rate without instance, intended for federation / LT-storage
        requests_ratiorate_job_verb_code: self.common {
          record: 'kubernetes::job_verb_code:apiserver_requests:ratio_rate5m',
          expr: 'sum without (instance)(%s)' % [
            metric.rules.requests_ratiorate_job_verb_code_instance.record,
          ],
        },
        // Useful for SLO and long-term views: job (only for `verb_slos`)
        slo_errors_ratiorate_job: self.common {
          record: 'kubernetes:job:apiserver_request_errors:ratio_rate5m',
          expr: 'sum by (job)(%s{verb=~"%s", code=~"5.."})' % [
            metric.rules.requests_ratiorate_job_verb_code_instance.record,
            metric.verb_slos,
          ],
        },

        // ### Latency ###
        // Create several r-rules from histogram_quantile() over  apiserver_request_latencies_bucket

        // Useful for dashboards: job, verb, instance
        latency_job_verb_instance: self.common {
          record: 'kubernetes:job_verb_instance:apiserver_latency:pctl%srate5m' % $.slo.latency_percentile,
          expr: |||
            histogram_quantile (
              0.%s,
              sum by (le, job, verb, instance)(
                rate(apiserver_request_latencies_bucket[5m])
              )
            ) / 1e3
          ||| % [$.slo.latency_percentile],
        },
        // Useful for alerting: job, verb
        latency_job_verb: self.common {
          record: 'kubernetes:job_verb:apiserver_latency:pctl%srate5m' % $.slo.latency_percentile,
          expr: |||
            histogram_quantile (
              0.%s,
              sum by (le, verb)(
                rate(apiserver_request_latencies_bucket[5m])
              )
            ) / 1e3 > 0
          ||| % [$.slo.latency_percentile],
        },

        // Useful for SLO and long-term views: job (only for `verb_slos`)
        slo_latency_job: self.common {
          record: 'kubernetes::job:apiserver_latency:pctl%srate5m' % $.slo.latency_percentile,
          expr: |||
            histogram_quantile (
              0.%s,
              sum by (le, job)(
                rate(apiserver_request_latencies_bucket{verb=~"%s"}[5m])
              )
            ) / 1e3
          ||| % [$.slo.latency_percentile, metric.verb_slos],
        },
        probe_success: self.common {
          record: 'kubernetes::job:probe_success',
          expr: |||
            sum by()(probe_success{provider="kubernetes", component="apiserver"})
          |||,
        },

        // SLOs: error ratio and latency below thresholds
        // The purpose of below metrics is to allow answering the question:
        //   How has this SLO done in the past <N> days ?
        //
        // As prometheus-2.3.x can't do e.g.:
        //   sum_over_time(kubernetes::job:slo_kube_api_ok[30d]) /
        //   sum_over_time(kubernetes::job:slo_kube_api_ok[30d] > -Inf)
        // b/c _over_time(<formula>) is not valid, but only plain _over_time(<metric>[time]),
        // so we create `slo_kube_api_sample` as a way to provide all-1's, to be able to:
        //   sum_over_time(kubernetes::job:slo_kube_api_ok[30d]) /
        //   sum_over_time(kubernetes::job:slo_kube_api_sample[30d])

        // metric to capture "SLO Ok"
        slo_ok: self.common {
          record: 'kubernetes::job:slo_kube_api_ok',
          expr: |||
            %s < bool %s * %s < bool %s
          ||| % [
            metric.rules.slo_errors_ratiorate_job.record,
            $.slo.error_ratio_threshold,
            metric.rules.slo_latency_job.record,
            $.slo.latency_threshold,
          ],
        },
        // metric always evaluating to 1 (with same labels as above)
        slo_sample: self.common {
          record: 'kubernetes::job:slo_kube_api_sample',
          expr: |||
            %s < bool Inf * %s < bool Inf
          ||| % [
            metric.rules.slo_errors_ratiorate_job.record,
            metric.rules.slo_latency_job.record,
          ],
        },
      },
    },
    kube_control_mgr: {
      local metric = self,
      work_duration_limit: 100,
      name: 'Kube Control Manager',
      graphs: {
        work_duration: $.grafana.common {
          title: 'Kube Control Manager work duration',
          formula: |||
            sum by (instance)(
              APIServiceRegistrationController_work_duration{quantile="0.9"}
            )
          |||,
          legend: '{{ instance }}',
          threshold: metric.work_duration_limit,
        },
      },
      alerts: {
        work_duration: $.prometheus.alerts_common {
          local alert = self,
          name: 'KubeControllerWorkDurationHigh',
          expr: |||
            sum by (instance)(
              APIServiceRegistrationController_work_duration{quantile="0.9"}
            ) > %s
          ||| % [metric.work_duration_limit],
          annotations: {
            summary: 'Kube Control Manager workqueue processing is slow',
            description: |||
              Issue: Kube Control Manager on {{ $labels.instance }} work duration is above %s: {{ $value }}
              Playbook: %s#%s
            ||| % [metric.work_duration_limit, runbook_url, alert.name],
          },
        },
      },
      rules: {},
    },
    kube_etcd: {
      local metric = self,
      etcd_latency_threshold: 2000,
      name: 'Kube Etcd',
      graphs: {
        latency: $.grafana.common {
          title: 'etcd 90th latency[ms] by (operation, instance)',
          formula: |||
            max by (operation, instance)(
              etcd_request_latencies_summary{job="kubernetes_apiservers",quantile="0.9"}
            )/ 1e3
          |||,
          legend: '{{ instance }} - {{ operation }}',
          threshold: metric.etcd_latency_threshold,
        },
      },
      alerts: {
        latency: $.prometheus.alerts_common {
          local alert = self,
          name: 'KubeEtcdLatencyHigh',
          expr: |||
            max by (instance)(
              etcd_request_latencies_summary{job="kubernetes_apiservers",quantile="0.9"}
            )/ 1e3 > %s
          ||| % [metric.etcd_latency_threshold],
          annotations: {
            summary: 'Etcd Latency is High',
            description: |||
              Issue: Kube Etcd latency on {{ $labels.instance }} above %s ms: {{ $value }}
              Playbook: %s#%s
            ||| % [metric.etcd_latency_threshold, runbook_url, alert.name],
          },
        },
      },
      rules: {},
    },
  },
}
