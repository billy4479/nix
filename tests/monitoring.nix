{
  pkgs,
  ruleFiles,
  scrapeConfigs,
  blackboxConfig,
}:
let
  scrapes = pkgs.writeText "monitoring-scrapes.json" (builtins.toJSON scrapeConfigs);
  tests = (pkgs.formats.yaml { }).generate "monitoring-rule-tests.yml" {
    rule_files = map toString ruleFiles;
    evaluation_interval = "1m";
    tests = [
      {
        interval = "1m";
        input_series = [
          {
            series = ''probe_success{job="blackbox-edge",service="public-edge",instance="https://87.106.25.93/health"}'';
            values = "0x5";
          }
        ];
        alert_rule_test = [
          {
            eval_time = "4m";
            alertname = "PublicEndpointDown";
            exp_alerts = [
              {
                exp_labels = {
                  job = "blackbox-edge";
                  service = "public-edge";
                  instance = "https://87.106.25.93/health";
                  severity = "critical";
                };
                exp_annotations.summary = "Public endpoint public-edge is unreachable";
              }
            ];
          }
        ];
      }
      {
        interval = "1m";
        input_series = [
          {
            series = ''probe_success{job="blackbox-edge",service="public-derp",instance="https://87.106.25.93/derp/probe"}'';
            values = "0x5";
          }
        ];
        alert_rule_test = [
          {
            eval_time = "4m";
            alertname = "PublicEndpointDown";
            exp_alerts = [
              {
                exp_labels = {
                  job = "blackbox-edge";
                  service = "public-derp";
                  instance = "https://87.106.25.93/derp/probe";
                  severity = "critical";
                };
                exp_annotations.summary = "Public endpoint public-derp is unreachable";
              }
            ];
          }
        ];
      }
      {
        interval = "1m";
        input_series = [
          {
            series = ''probe_success{job="blackbox-edge",service="public-derp"}'';
            values = "1x5";
          }
        ];
        alert_rule_test = [
          {
            eval_time = "4m";
            alertname = "PublicEndpointDown";
            exp_alerts = [ ];
          }
        ];
      }
      {
        interval = "1m";
        input_series = [
          {
            series = "certbot_renew_last_success_seconds";
            values = "0x2400";
          }
        ];
        alert_rule_test = [
          {
            eval_time = "38h";
            alertname = "CertificateRenewalOverdue";
            exp_alerts = [
              {
                exp_labels.severity = "warning";
                exp_annotations.summary = "Certificate renewal and DERP certificate upload have not completed recently";
              }
            ];
          }
        ];
      }
      {
        interval = "1m";
        input_series = [
          {
            series = "certbot_renew_last_success_seconds";
            values = "0+60x2400";
          }
        ];
        alert_rule_test = [
          {
            eval_time = "38h";
            alertname = "CertificateRenewalOverdue";
            exp_alerts = [ ];
          }
        ];
      }
      {
        interval = "1m";
        input_series = [ ];
        alert_rule_test = [
          {
            eval_time = "61m";
            alertname = "CertificateRenewalOverdue";
            exp_alerts = [
              {
                exp_labels.severity = "warning";
                exp_annotations.summary = "Certificate renewal and DERP certificate upload have not completed recently";
              }
            ];
          }
        ];
      }
      {
        interval = "1m";
        input_series = [
          {
            series = ''probe_success{job="blackbox-http",service="jackett",instance="http://10.0.1.8:9112/health"}'';
            values = "0x12";
          }
        ];
        alert_rule_test = [
          {
            eval_time = "6m";
            alertname = "ContainerDown";
            exp_alerts = [
              {
                exp_labels = {
                  job = "blackbox-http";
                  service = "jackett";
                  instance = "http://10.0.1.8:9112/health";
                  severity = "critical";
                };
                exp_annotations.summary = "jackett is unreachable";
                exp_annotations.description = "The blackbox probe against http://10.0.1.8:9112/health has been failing for more than 5 minutes.";
              }
            ];
          }
        ];
      }
      {
        # The slow job scrapes every 6m, past the 5m lookback default, so a
        # probe_success sample goes stale between scrapes and the == 0
        # selector would keep resetting the pending timer. last_over_time
        # in the alert must bridge the gap.
        interval = "6m";
        input_series = [
          {
            series = ''probe_success{job="blackbox-http-slow",service="byparr",instance="http://10.0.1.134:8191/health"}'';
            values = "1 0 0";
          }
        ];
        alert_rule_test = [
          {
            eval_time = "13m";
            alertname = "ContainerDown";
            exp_alerts = [
              {
                exp_labels = {
                  job = "blackbox-http-slow";
                  service = "byparr";
                  instance = "http://10.0.1.134:8191/health";
                  severity = "critical";
                };
                exp_annotations.summary = "byparr is unreachable";
                exp_annotations.description = "The blackbox probe against http://10.0.1.134:8191/health has been failing for more than 5 minutes.";
              }
            ];
          }
        ];
      }
    ];
  };
in
pkgs.runCommand "monitoring-alert-regression-test"
  {
    nativeBuildInputs = [
      pkgs.prometheus.cli
      (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
    ];
  }
  # sh
  ''
    promtool check rules ${pkgs.lib.escapeShellArgs (map toString ruleFiles)}
    promtool test rules ${tests}
    python ${./edge-probes.py} ${scrapes} ${blackboxConfig}
    touch "$out"
  ''
