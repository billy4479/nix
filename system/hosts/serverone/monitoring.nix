{
  config,
  lib,
  pkgs,
  ...
}:
let
  yamlFormat = pkgs.formats.yaml { };

  # Always connect to the public VPS IP, not a split-DNS container address.
  # Pin both Host and SNI so TLS and routing are checked end to end.
  edgeTargets = [
    {
      name = "public-headscale";
      host = "headscale.polpetta.online";
      path = "/health";
    }
    {
      name = "public-derp";
      host = "derp.polpetta.online";
      path = "/derp/probe";
    }
    {
      name = "public-homepage";
      host = "polpetta.online";
      path = "/";
    }
  ];
  edgeModules = lib.listToAttrs (
    map (target: {
      name = target.name;
      value = {
        prober = "http";
        timeout = "30s";
        http = {
          preferred_ip_protocol = "ip4";
          follow_redirects = false;
          valid_status_codes = [ 200 ];
          headers.Host = target.host;
          tls_config.server_name = target.host;
        };
      };
    }) edgeTargets
  );

  # Static blackbox probe modules: plain http for the container web UIs, an
  # https module pinning the grafana internal vhost (used to watch the
  # wildcard certificate), an http module for services whose only unauth
  # answers are 401/404 (which still prove the HTTP server is alive) and a
  # plain tcp module for non-http services. All modules allow 30s per
  # probe: some health endpoints are legitimately slow (e.g. they drive a
  # page load through a headless browser), and a tight budget turns a
  # healthy but slow app into flapping ContainerDown alerts. A probe only
  # burns the budget when its target actually hangs, so the uniform 30s
  # costs nothing on healthy targets. The scrape jobs carry a matching
  # 35s scrape_timeout on a 1m interval; a service needing more than 30s
  # sets probe.timeout and lands in the slow job below.
  staticModules = {
    http_2xx = {
      prober = "http";
      timeout = "30s";
      http = {
        preferred_ip_protocol = "ip4";
      };
    };
    http_unauth = {
      prober = "http";
      timeout = "30s";
      http = {
        preferred_ip_protocol = "ip4";
        # Don't follow auth redirects: an unauthenticated probe that lands
        # on the IdP would fail even though the service is alive.
        follow_redirects = false;
        # blackbox_exporter only accepts literal status codes here; 401 is
        # calendar-proxy without a token, 404 is agent-up on /, 302/403 are
        # the OIDC-gated services (ff, headplane) bouncing to tsidp.
        valid_status_codes = [
          200
          301
          302
          401
          403
          404
        ];
      };
    };
    https_internal = {
      prober = "http";
      timeout = "30s";
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
      timeout = "30s";
    };
  };

  # LAN probes verify the services themselves; this one goes out to the
  # public edge and hairpins back (serverone → vps SNI demuxer → wireguard
  # tunnel → nginx → calendar-proxy), so it fails when the tunnel, the vps
  # DNAT or the demuxer break — which the LAN probes cannot see.
  httpProbeTargets = config.polpetta.generated.probeHttpTargets ++ [
    {
      name = "public-edge";
      # Answers 401 without a token, which http_unauth accepts; the
      # wildcard certificate covers the public name.
      url = "https://calendar-proxy.polpetta.online";
      module = "http_unauth";
    }
  ];

  # Probes with an overridden timeout cannot share the fast job: a scrape
  # is cut off at its scrape_timeout, and prometheus refuses a scrape
  # timeout above the job interval. The slow job gives them 5m30s per
  # scrape on a 6m interval.
  slowHttpTargets = lib.filter (t: t ? timeout) httpProbeTargets;
  fastHttpTargets = lib.filter (t: !(t ? timeout)) httpProbeTargets;

  # blackbox_exporter takes http headers and the module timeout only from
  # the module config, so a service with probe.headers or probe.timeout
  # gets its own module: a copy of its base module with both merged in.
  # The generated target carries the base module name and the override
  # (see services/module.nix).
  customModules = lib.listToAttrs (
    map (t: {
      name = t.module;
      value = lib.recursiveUpdate staticModules.${t.baseModule} (
        (lib.optionalAttrs (t ? headers) { http.headers = t.headers; })
        // (lib.optionalAttrs (t ? timeout) { inherit (t) timeout; })
      );
    }) (lib.filter (t: (t ? headers) || (t ? timeout)) httpProbeTargets)
  );

  blackboxConfig = yamlFormat.generate "blackbox-exporter.yml" {
    modules = staticModules // customModules // edgeModules;
  };

  alertRules = yamlFormat.generate "serverone-alerts.yml" {
    groups = [
      {
        name = "host";
        rules = [
          {
            alert = "NodeExporterDown";
            expr = "up{job=\"node\"} == 0";
            for = "3m";
            labels.severity = "critical";
            annotations = {
              summary = "Local node_exporter {{ $labels.instance }} is unreachable";
              description = "node_exporter has been unreachable for more than 3 minutes.";
            };
          }
          {
            alert = "MonitoringTargetDown";
            expr = "up == 0";
            for = "5m";
            labels.severity = "warning";
            annotations.summary = "Monitoring target {{ $labels.instance }} cannot be scraped";
          }
          {
            alert = "PublicEndpointDown";
            expr = "probe_success{job=\"blackbox-edge\"} == 0";
            for = "3m";
            labels.severity = "critical";
            annotations.summary = "Public endpoint {{ $labels.service }} is unreachable";
          }
          {
            alert = "CertificateRenewalOverdue";
            expr = "time() - certbot_renew_last_success_seconds > 36 * 3600 or absent(certbot_renew_last_success_seconds)";
            for = "1h";
            labels.severity = "warning";
            annotations.summary = "Certificate renewal and DERP certificate upload have not completed recently";
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
            # storage.nix schedules a scrub on the 1st of every month with up
            # to 6h of random delay, so the longest healthy gap between two
            # scrubs is ~31 days. 35 days therefore only fires when a
            # scheduled scrub failed to run or complete.
            expr = "time() - zpool_scrub_last_completed_seconds > 35 * 24 * 3600 and zpool_scrub_state == 0";
            for = "1h";
            labels.severity = "warning";
            annotations = {
              summary = "Scrub overdue on ZFS pool {{ $labels.pool }}";
              description = "The last scrub on pool {{ $labels.pool }} completed more than 35 days ago (monthly scrub expected).";
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
            # last_over_time bridges the 6m sample gaps of the slow job:
            # with the default 5m lookback a blackbox-http-slow sample goes
            # stale between scrapes and would keep resetting the timer.
            alert = "ContainerDown";
            expr = "last_over_time(probe_success{job=~\"blackbox-(http|tcp|http-slow)\"}[10m]) == 0";
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
  # node_exporter textfile collector instead (runs as root). It also emits
  # per-pool IO counters, which is why the timer runs at one minute: any
  # coarser and the rates would be too jumpy for the dashboard.
  zpoolTextfileScript =
    pkgs.writeShellScript "prometheus-zpool-textfile" # sh
      ''
        set -eu

        dir=/var/lib/prometheus-node-exporter
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

          # zfs_exporter has no IO metrics either; `zpool iostat -pH` gives
          # per-pool counters (ops and bytes, cumulative since boot) which
          # Prometheus turns into rates. Columns: name alloc free reads
          # writes read_bytes write_bytes.
          zpool iostat -pH | while read -r pool _ _ reads writes rbytes wbytes; do
            printf 'zpool_io_reads_total{pool="%s"} %s\n' "$pool" "$reads"
            printf 'zpool_io_writes_total{pool="%s"} %s\n' "$pool" "$writes"
            printf 'zpool_io_read_bytes_total{pool="%s"} %s\n' "$pool" "$rbytes"
            printf 'zpool_io_write_bytes_total{pool="%s"} %s\n' "$pool" "$wbytes"
          done
        } >"$tmp"

        # mktemp creates the file 0600 root-owned; node_exporter runs as the
        # node-exporter user and would never read it.
        chmod 644 "$tmp"
        mv "$tmp" "$dir/zpool.prom"
      '';

  # Relabeling boilerplate for scraping the blackbox exporter: the target
  # moves into the `target` query parameter and the exporter address is set
  # statically. Targets may carry a `module` label to select a probe module
  # other than the job default.
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
      source_labels = [ "module" ];
      regex = "(.+)";
      target_label = "__param_module";
    }
    {
      target_label = "__address__";
      replacement = "127.0.0.1:9115";
    }
  ];

  # All probes are generated from polpetta.services: http targets from the
  # web endpoints (polpetta.generated.probeHttpTargets), tcp targets from raw
  # ports flagged `probe` (polpetta.generated.probeTcpTargets). Per-service
  # path/module overrides live in each service file.
  tcpProbeTargets = config.polpetta.generated.probeTcpTargets;

  # Each probe target carries a `service` label so the dashboards and the
  # ContainerDown alert can show a human-readable name. An optional `module`
  # label selects the blackbox module for that target.
  probeStaticConfigs =
    probeAttr: targets:
    map (t: {
      targets = [ t.${probeAttr} ];
      labels = {
        service = t.name;
      }
      // lib.optionalAttrs (t ? module) {
        module = t.module;
      };
    }) targets;
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
    # One listener serves localhost scrapes and Grafana on the bridge; the
    # firewall opens it only on nerdctl0, not the LAN or tailnet interfaces.
    listenAddress = "0.0.0.0";
    retentionTime = "90d";

    globalConfig = {
      scrape_interval = "30s";
      evaluation_interval = "30s";
    };

    exporters = {
      node = {
        enable = true;
        listenAddress = "127.0.0.1";
        # systemd is not part of node_exporter's built-in defaults
        enabledCollectors = [ "systemd" ];
        extraFlags = [
          "--collector.textfile.directory=/var/lib/prometheus-node-exporter"
        ];
      };

      smartctl = {
        enable = true;
        listenAddress = "127.0.0.1";
      };

      zfs = {
        enable = true;
        listenAddress = "127.0.0.1";
      };

      nginx = {
        enable = true;
        listenAddress = "127.0.0.1";
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
        job_name = "blackbox-edge";
        metrics_path = "/probe";
        # Probe modules allow 30s; the default 10s scrape timeout would
        # cut a slow probe short before it can report probe_success = 0.
        scrape_interval = "1m";
        scrape_timeout = "35s";
        static_configs = map (target: {
          targets = [ "https://87.106.25.93${target.path}" ];
          labels = {
            service = target.name;
            module = target.name;
          };
        }) edgeTargets;
        relabel_configs = blackboxRelabelConfigs;
      }
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
        # The HTTP modules allow 30s per probe; the default 10s scrape
        # timeout would cut a slow probe short before it can report
        # probe_success = 0, so give the scrape 35s on a 1m interval.
        scrape_interval = "1m";
        scrape_timeout = "35s";
        params = {
          module = [ "http_2xx" ];
        };
        static_configs = probeStaticConfigs "url" fastHttpTargets;
        relabel_configs = blackboxRelabelConfigs;
      }
      {
        job_name = "blackbox-http-slow";
        metrics_path = "/probe";
        # scrape_timeout must exceed the largest module timeout here or a
        # failing probe's result would be lost to a scrape abort, and
        # prometheus refuses a scrape timeout above the job interval.
        params.module = [ "http_2xx" ];
        scrape_interval = "6m";
        scrape_timeout = "5m30s";
        static_configs = probeStaticConfigs "url" slowHttpTargets;
        relabel_configs = blackboxRelabelConfigs;
      }
      {
        job_name = "blackbox-tcp";
        metrics_path = "/probe";
        # tcp_connect allows 30s like every probe module.
        scrape_interval = "1m";
        scrape_timeout = "35s";
        params = {
          module = [ "tcp_connect" ];
        };
        static_configs = probeStaticConfigs "address" tcpProbeTargets;
        relabel_configs = blackboxRelabelConfigs;
      }
      {
        job_name = "blackbox-https";
        metrics_path = "/probe";
        # https_internal allows 30s per probe like the other HTTP modules.
        scrape_interval = "1m";
        scrape_timeout = "35s";
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
    listenAddress = "127.0.0.1";
    extraOptions = [
      "--containerd=/run/containerd/containerd.sock"
      # cAdvisor only watches the "k8s.io" namespace by default, our
      # containers live in the "default" one.
      "--containerd-namespace=default"
    ];
  };

  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1";
    extraFlags = [ "--cluster.listen-address=" ];
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

  systemd.tmpfiles.rules = [ "d /var/lib/prometheus-node-exporter 0755 root root -" ];

  systemd.services.prometheus-zpool-textfile = {
    description = "Export zpool scrub, error and IO status to the node_exporter textfile collector";
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
      OnUnitActiveSec = "1min";
    };
  };

  # Grafana runs in a container and reaches Prometheus through the bridge
  # gateway address (10.0.1.1), which lands on the nerdctl0 INPUT chain.
  networking.firewall.interfaces."nerdctl0".allowedTCPPorts = [ config.services.prometheus.port ];
}
