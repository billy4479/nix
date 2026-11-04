{ pkgs, ruleFiles }:
let
  tests = (pkgs.formats.yaml { }).generate "monitoring-rule-tests.yml" {
    rule_files = map toString ruleFiles;
    evaluation_interval = "1m";
    tests = [
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
    ];
  };
in
pkgs.runCommand "monitoring-alert-regression-test"
  {
    nativeBuildInputs = [ pkgs.prometheus.cli ];
  }
  # sh
  ''
    promtool check rules ${pkgs.lib.escapeShellArgs (map toString ruleFiles)}
    promtool test rules ${tests}
    touch "$out"
  ''
