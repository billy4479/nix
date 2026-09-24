{
  config,
  lib,
  pkgs,
  ...
}:
let
  yamlFormat = pkgs.formats.yaml { };

  # Blackbox probe modules: plain http for the container web UIs, an
  # https module pinning the grafana internal vhost (used to watch the
  # wildcard certificate) and a plain tcp module for non-http services.
  blackboxConfig = yamlFormat.generate "blackbox-exporter.yml" {
    modules = {
      http_2xx = {
        prober = "http";
        timeout = "5s";
        http = {
          preferred_ip_protocol = "ip4";
        };
      };
      https_internal = {
        prober = "http";
        timeout = "5s";
        http = {
          preferred_ip_protocol = "ip4";
          headers = {
            Host = "grafana.internal.polpetta.online";
          };
          tls_config = {
            server_name = "grafana.internal.polpetta.online";
          };
        };
      };
      tcp_connect = {
        prober = "tcp";
        timeout = "5s";
      };
    };
  };

  alertRules = yamlFormat.generate "serverone-alerts.yml" {
    groups = [
      {
        name = "host";
        rules = [
          {
            alert = "HostDown";
            expr = "up{job=\"node\"} == 0";
            for = "3m";
            labels.severity = "critical";
            annotations = {
              summary = "Host {{ $labels.instance }} is down";
              description = "node_exporter has been unreachable for more than 3 minutes.";
            };
          }
          {
            alert = "SystemdUnitFailed";
            expr = "node_systemd_unit_state{state=\"failed\", name!~\"(user@|session-\\\\d+\\\\.scope).*\"} == 1";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Systemd unit {{ $labels.name }} failed on {{ $labels.instance }}";
              description = "The unit has been in the failed state for more than 5 minutes.";
            };
          }
        ];
      }
      {
        name = "zfs";
        rules = [
          {
            alert = "ZfsPoolUsageWarning";
            expr = "zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.80";
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "ZFS pool {{ $labels.pool }} is above 80% usage";
              description = "Pool {{ $labels.pool }} is using {{ $value | humanizePercentage }} of its capacity.";
            };
          }
          {
            alert = "ZfsPoolUsageCritical";
            expr = "zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.90";
            for = "10m";
            labels.severity = "critical";
            annotations = {
              summary = "ZFS pool {{ $labels.pool }} is above 90% usage";
              description = "Pool {{ $labels.pool }} is using {{ $value | humanizePercentage }} of its capacity.";
            };
          }
          {
            alert = "ZfsPoolDegraded";
            expr = "zfs_pool_health == 1";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "ZFS pool {{ $labels.pool }} is degraded";
              description = "Redundancy has been lost on pool {{ $labels.pool }}, replace or reattach the failed device.";
            };
          }
          {
            alert = "ZfsPoolFailed";
            expr = "zfs_pool_health >= 2";
            for = "1m";
            labels.severity = "critical";
            annotations = {
              summary = "ZFS pool {{ $labels.pool }} is failed";
              description = "Pool {{ $labels.pool }} is not healthy (status >= FAULTED), data may be unavailable.";
            };
          }
          {
            alert = "ZfsDataErrors";
            expr = "zpool_data_errors > 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "ZFS pool {{ $labels.pool }} reports data errors";
              description = "`zpool status` reports permanent errors on pool {{ $labels.pool }}.";
            };
          }
          {
            alert = "ZfsScrubOverdue";
            expr = "time() - zpool_scrub_last_completed_seconds > 21 * 24 * 3600 and zpool_scrub_state == 0";
            for = "1h";
            labels.severity = "warning";
            annotations = {
              summary = "Scrub overdue on ZFS pool {{ $labels.pool }}";
              description = "The last scrub on pool {{ $labels.pool }} completed more than 21 days ago.";
            };
          }
        ];
      }
      {
        name = "smart";
        rules = [
          {
            alert = "SmartDeviceFailing";
            expr = "smartctl_device_smart_status == 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "SMART reports {{ $labels.device }} failing";
              description = "The overall SMART health self-assessment of {{ $labels.device }} is failing.";
            };
          }
          {
            alert = "SmartCriticalWarning";
            expr = "smartctl_device_critical_warning != 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "SMART critical warning on {{ $labels.device }}";
              description = "Device {{ $labels.device }} raised a critical warning ({{ $value }}).";
            };
          }
          {
            alert = "SmartDeviceHot";
            expr = "smartctl_device_temperature > 60";
            for = "10m";
            labels.severity = "warning";
            annotations = {
              summary = "{{ $labels.device }} is hot ({{ $value }}°C)";
              description = "Device {{ $labels.device }} has been above 60°C for more than 10 minutes.";
            };
          }
        ];
      }
      {
        name = "containers";
        rules = [
          {
            alert = "ContainerDown";
            expr = "probe_success{job=~\"blackbox-(http|tcp)\"} == 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "{{ $labels.service }} is unreachable";
              description = "The blackbox probe against {{ $labels.instance }} has been failing for more than 5 minutes.";
            };
          }
          {
            alert = "CertificateExpiringSoon";
            expr = "probe_ssl_earliest_cert_expiry - time() < 14 * 24 * 3600";
            for = "1h";
            labels.severity = "warning";
            annotations = {
              summary = "Certificate for {{ $labels.instance }} expires in less than 14 days";
              description = "The certificate served by {{ $labels.instance }} expires in {{ $value | humanizeDuration }}.";
            };
          }
        ];
      }
    ];
  };

  # zfs_exporter has no scrub metrics, so parse `zpool status` into the
  # node_exporter textfile collector instead (runs as root).
  zpoolTextfileScript =
    pkgs.writeShellScript "prometheus-zpool-textfile" # sh
      ''
        set -eu

        dir=/run/prometheus-node-exporter
        mkdir -p "$dir"
        tmp=$(mktemp "$dir/.zpool.XXXXXX")
        trap 'rm -f "$tmp"' EXIT

        {
          echo "# zpool data collected by prometheus-zpool-textfile"
          for pool in $(zpool list -H -o name); do
            status=$(zpool status "$pool")
            scan=$(printf '%s\n' "$status" | sed -n 's/^[[:space:]]*scan:[[:space:]]*//p' | head -n 1)
            errors=$(printf '%s\n' "$status" | sed -n 's/^[[:space:]]*errors:[[:space:]]*//p' | head -n 1)

            state=0
            case "$scan" in
              "scrub in progress"*) state=1 ;;
              "resilver in progress"*) state=2 ;;
            esac
            printf 'zpool_scrub_state{pool="%s"} %d\n' "$pool" "$state"

            # "scan: scrub repaired 0B in 0:1:23 with 0 errors on Sat Jan  1 03:00:00 2026"
            when=$(printf '%s' "$scan" | sed -n 's/.* on \(.*\)$/\1/p')
            if [ -n "$when" ]; then
              ts=$(date -d "$when" +%s 2>/dev/null || true)
              if [ -n "''${ts:-}" ]; then
                printf 'zpool_scrub_last_completed_seconds{pool="%s"} %d\n' "$pool" "$ts"
              fi
            fi

            err=0
            if [ "$errors" != "No known data errors" ]; then
              err=1
            fi
            printf 'zpool_data_errors{pool="%s"} %d\n' "$pool" "$err"
          done
        } > "$tmp"

        # mktemp creates the file 0600 root-owned; node_exporter runs as the
        # node-exporter user and would never read it.
        chmod 644 "$tmp"
        mv "$tmp" "$dir/zpool.prom"
      '';

  # Relabeling boilerplate for scraping the blackbox exporter: the target
  # moves into the `target` query parameter and the exporter address is set
  # statically.
  blackboxRelabelConfigs = [
    {
      source_labels = [ "__address__" ];
      target_label = "__param_target";
    }
    {
      source_labels = [ "__param_target" ];
      target_label = "instance";
    }
    {
      target_label = "__address__";
      replacement = "127.0.0.1:9115";
    }
  ];

  # Services with a web UI, probed with the http_2xx module. Keep in sync
  # with the table in docs/CONTAINERS.md.
  httpProbeTargets = [
    { name = "syncthing"; url = "http://10.0.1.2:8384"; }
    { name = "immich"; url = "http://10.0.1.3:2283"; }
    { name = "calendar-proxy"; url = "http://10.0.1.4:4479"; }
    { name = "qbittorrent"; url = "http://10.0.1.5:8080"; }
    { name = "radarr"; url = "http://10.0.1.7:7878"; }
    { name = "jackett"; url = "http://10.0.1.8:9117"; }
    { name = "sonarr"; url = "http://10.0.1.9:8989"; }
    { name = "jellyfin"; url = "http://10.0.1.10:8096"; }
    { name = "stirling-pdf"; url = "http://10.0.1.12:8080"; }
    { name = "mc-runner"; url = "http://10.0.1.13:4479"; }
    { name = "opencloud"; url = "http://10.0.1.14:9200"; }
    { name = "headscale"; url = "http://10.0.1.15:8080"; }
    { name = "headplane"; url = "http://10.0.1.16:3000"; }
    { name = "ff"; url = "http://10.0.1.17:4479"; }
    { name = "giuoco-del-divertimento"; url = "http://10.0.1.18:4479"; }
    { name = "searxng"; url = "http://10.0.1.19:8888"; }
    { name = "lunamultiplayer"; url = "http://10.0.1.20:8900"; }
    { name = "openchamber"; url = "http://10.0.1.21:3000"; }
    { name = "agent-up"; url = "http://10.0.1.22:3000"; }
    { name = "grafana"; url = "http://10.0.1.23:3000"; }
    { name = "byparr"; url = "http://10.0.1.134:8191"; }
  ];

  tcpProbeTargets = [
    { name = "bind9"; address = "10.0.1.11:53"; }
    { name = "immich-valkey"; address = "10.0.1.129:6379"; }
    { name = "immich-postgres"; address = "10.0.1.130:5432"; }
  ];

  # Each probe target carries a `service` label so the dashboards and the
  # ContainerDown alert can show a human-readable name.
  probeStaticConfigs = probeAttr: targets: map (
    t: {
      targets = [ t.${probeAttr} ];
      labels = {
        service = t.name;
      };
    }
  ) targets;
in
{
  # The shared telegram-bot secret block (token + chat id) lives once per
  # host in the secrets repo; select its nested keys here.
  sops.secrets = {
    telegram-bot-token.key = "telegram-bot/token";
    telegram-bot-chat-id.key = "telegram-bot/chat-id";
  };

  # Alertmanager interpolates envsubst-style variables from environmentFile
  # into its config; render them from the sops secrets.
  sops.templates."alertmanager-telegram-env" = {
    content = # sh
      ''
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder."telegram-bot-token"}
        TELEGRAM_CHAT_ID=${config.sops.placeholder."telegram-bot-chat-id"}
      '';
    restartUnits = [ "alertmanager.service" ];
  };

  services.prometheus = {
    enable = true;
    retentionTime = "90d";

    globalConfig = {
      scrape_interval = "30s";
      evaluation_interval = "30s";
    };

    exporters = {
      node = {
        enable = true;
        # systemd is not part of node_exporter's built-in defaults
        enabledCollectors = [ "systemd" ];
        extraFlags = [
          "--collector.textfile.directory=/run/prometheus-node-exporter"
        ];
      };

      smartctl.enable = true;

      zfs.enable = true;

      nginx = {
        enable = true;
        scrapeUri = "http://10.0.1.6:8082/stub_status";
      };

      blackbox = {
        enable = true;
        listenAddress = "127.0.0.1";
        configFile = blackboxConfig;
      };
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          { targets = [ "127.0.0.1:9100" ]; }
        ];
      }
      {
        job_name = "smartctl";
        static_configs = [
          { targets = [ "127.0.0.1:9633" ]; }
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          { targets = [ "127.0.0.1:9134" ]; }
        ];
      }
      {
        job_name = "cadvisor";
        static_configs = [
          { targets = [ "127.0.0.1:8080" ]; }
        ];
        # The containerd factory exposes the real container name only as
        # the `container_label_nerdctl_name` label; copy it into a lean
        # `container` label and drop the bulky labels from every sample.
        metric_relabel_configs = [
          {
            source_labels = [ "container_label_nerdctl_name" ];
            target_label = "container";
          }
          {
            action = "labeldrop";
            regex = "container_label_.*";
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [
          { targets = [ "127.0.0.1:9113" ]; }
        ];
      }
      {
        job_name = "blackbox-http";
        metrics_path = "/probe";
        params = {
          module = [ "http_2xx" ];
        };
        static_configs = probeStaticConfigs "url" httpProbeTargets;
        relabel_configs = blackboxRelabelConfigs;
      }
      {
        job_name = "blackbox-tcp";
        metrics_path = "/probe";
        params = {
          module = [ "tcp_connect" ];
        };
        static_configs = probeStaticConfigs "address" tcpProbeTargets;
        relabel_configs = blackboxRelabelConfigs;
      }
      {
        job_name = "blackbox-https";
        metrics_path = "/probe";
        params = {
          module = [ "https_internal" ];
        };
        static_configs = [
          { targets = [ "https://10.0.1.6" ]; }
        ];
        relabel_configs = blackboxRelabelConfigs;
      }
    ];

    ruleFiles = [ alertRules ];

    alertmanagers = [
      {
        static_configs = [
          { targets = [ "127.0.0.1:9093" ]; }
        ];
      }
    ];
  };

  services.cadvisor = {
    enable = true;
    extraOptions = [
      "--containerd=/run/containerd/containerd.sock"
      # cAdvisor only watches the "k8s.io" namespace by default, our
      # containers live in the "default" one.
      "--containerd-namespace=default"
    ];
  };

  services.prometheus.alertmanager = {
    enable = true;
    # The rendered config contains secret placeholders, amtool cannot
    # validate them before envsubst runs.
    checkConfig = false;
    environmentFile = config.sops.templates."alertmanager-telegram-env".path;
    configText = # yaml
      ''
        global:
          resolve_timeout: 5m

        route:
          receiver: telegram
          group_by: ["alertname", "instance"]
          group_wait: 30s
          group_interval: 5m
          repeat_interval: 4h

        receivers:
          - name: telegram
            telegram_configs:
              - bot_token: "$TELEGRAM_BOT_TOKEN"
                chat_id: $TELEGRAM_CHAT_ID
                send_resolved: true
      '';
  };

  systemd.services.prometheus-zpool-textfile = {
    description = "Export zpool scrub and error status to the node_exporter textfile collector";
    after = [ "prometheus-node-exporter.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = zpoolTextfileScript;
    };
    path = with pkgs; [
      config.boot.zfs.package
      coreutils
      gnugrep
      gnused
    ];
  };

  systemd.timers.prometheus-zpool-textfile = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
    };
  };

  # Grafana runs in a container and reaches Prometheus through the bridge
  # gateway address (10.0.1.1), which lands on the nerdctl0 INPUT chain.
  networking.firewall.interfaces."nerdctl0".allowedTCPPorts = [ config.services.prometheus.port ];
}
