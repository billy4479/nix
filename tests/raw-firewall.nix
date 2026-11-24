{
  pkgs,
  ruleset,
  adminRuleset,
  rawUnit,
  cniConfig,
  prometheusTable,
  prometheusInputRules,
}:
let
  portmap = builtins.head (builtins.filter (p: p.type == "portmap") cniConfig.plugins);
  portmapConfig = pkgs.writeText "test-portmap.json" (
    builtins.toJSON (
      portmap
      // {
        inherit (cniConfig) cniVersion name;
        runtimeConfig.portMappings = [
          {
            hostPort = 1053;
            containerPort = 53;
            protocol = "tcp";
          }
        ];
        prevResult = {
          inherit (cniConfig) cniVersion;
          ips = [ { address = "10.0.1.11/24"; } ];
        };
      }
    )
  );
  cni = "CNI_CONTAINERID=test-dns CNI_NETNS=/run/netns/dns CNI_IFNAME=eth0 CNI_PATH=${pkgs.cni-plugins}/bin ${pkgs.cni-plugins}/bin/portmap < ${portmapConfig}";
in
pkgs.testers.runNixOSTest {
  name = "raw-port-isolation";
  # Also runnable in the development container without /dev/kvm.
  requiredFeatures.kvm = false;
  requiredFeatures.nixos-test = false;
  qemu.forceAccel = false;
  nodes.machine = {
    imports = [
      (import ../system/hosts/serverone/firewall.nix {
        qbtIp = "10.0.1.5";
        wgMark = "0x1";
      })
    ];
    virtualisation.memorySize = 768;
    systemd.services.polpetta-raw-firewall = {
      inherit (rawUnit)
        serviceConfig
        reloadIfChanged
        before
        after
        requires
        ;
      wantedBy = [ "multi-user.target" ];
    };
    # A dummy engine uses the same service name/order as production. No actual
    # container engine or application data is required to check fail-closed start.
    systemd.services.containerd = {
      requires = [ "polpetta-raw-firewall.service" ];
      script = "touch /tmp/containerd-started";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
    environment.systemPackages = [
      pkgs.conntrack-tools
      pkgs.valkey
      pkgs.netcat-openbsd
    ];
    environment.etc."raw-firewall.nft".source = ruleset;
    environment.etc."raw-firewall-admin.nft".source = adminRuleset;
    networking.nftables.tables.serverone-prometheus = prometheusTable;
    networking.firewall.extraInputRules = prometheusInputRules;
  };
  testScript = # python
    ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("polpetta-raw-firewall.service")
      machine.succeed(
          "ip link add nerdctl0 type bridge; ip link set nerdctl0 up; ip addr add 10.0.1.1/24 dev nerdctl0"
      )
      for name, suffix in [
          ("immich", 3),
          ("outline", 24),
          ("nginx", 6),
          ("grafana", 23),
          ("peer", 21),
          ("edge", 131),
          ("redis", 129),
          ("outline-redis", 133),
          ("dns", 11),
          ("torrent", 5),
          ("radarr", 7),
          ("sonarr", 9),
      ]:
          machine.succeed(
              f"ip netns add {name}; ip link add v-{suffix} type veth peer name eth0 netns {name}; ip link set v-{suffix} master nerdctl0; ip link set v-{suffix} up; ip -n {name} link set lo up; ip -n {name} link set eth0 up; ip -n {name} addr add 10.0.1.{suffix}/24 dev eth0; ip -n {name} route add default via 10.0.1.1"
          )
      machine.succeed(
          "ip netns add vpn; ip link add tailscale0 type veth peer name eth0 netns vpn; ip addr add 100.64.0.1/24 dev tailscale0; ip link set tailscale0 up; ip -n vpn link set eth0 up; ip -n vpn addr add 100.64.0.7/24 dev eth0; ip -n vpn route add 10.0.1.0/24 via 100.64.0.1"
      )
      for namespace, host, router, subnet, peer in [
          ("uplink", "enp2s0", "192.0.2.1", "24", "192.0.2.2"),
          ("tunnel", "wg0", "10.100.0.2", "24", "10.100.0.1"),
      ]:
          machine.succeed(
              f"ip netns add {namespace}; ip link add {host} type veth peer name eth0 netns {namespace}; ip addr add {router}/{subnet} dev {host}; ip link set {host} up; ip -n {namespace} addr add {peer}/{subnet} dev eth0; ip -n {namespace} link set eth0 up; ip -n {namespace} route add 10.0.1.0/24 via {router}"
          )
          machine.succeed(
              f'ip netns exec {namespace} valkey-server --bind {peer} --protected-mode no --save "" --daemonize yes --dir /tmp --pidfile /tmp/{namespace}.pid --logfile /tmp/{namespace}.log'
          )
      machine.succeed("ip -n vpn route add default via 100.64.0.1")
      machine.succeed(
          "ip -6 addr add fd7a:115c:a1e0::1/64 dev tailscale0 nodad; ip -n vpn -6 addr add fd7a:115c:a1e0::7/64 dev eth0 nodad; ip -n vpn -6 route add default via fd7a:115c:a1e0::1"
      )
      machine.succeed(
          'ip -6 addr add 2001:db8::1/64 dev enp2s0 nodad; ip -n uplink -6 addr add 2001:db8::2/64 dev eth0 nodad; ip netns exec uplink valkey-server --bind 2001:db8::2 --protected-mode no --save "" --daemonize yes --dir /tmp --pidfile /tmp/uplink6.pid --logfile /tmp/uplink6.log'
      )
      for namespace, address in [("redis", "10.0.1.129"), ("outline-redis", "10.0.1.133")]:
          machine.succeed(
              f'ip netns exec {namespace} valkey-server --bind {address} --port 6379 --protected-mode no --save "" --daemonize yes --dir /tmp --pidfile /tmp/{namespace}.pid --logfile /tmp/{namespace}.log'
          )
      machine.succeed(
          'ip netns exec dns valkey-server --bind 10.0.1.11 --port 53 --protected-mode no --save "" --daemonize yes --dir /tmp --pidfile /tmp/dns-test.pid --logfile /tmp/dns-test.log'
      )
      # Check the actual source seen by the receiver, not just reachability.
      machine.succeed(
          "ip netns exec vpn valkey-cli -h 10.0.1.11 -p 53 client info | grep 'addr=100.64.0.7:'"
      )
      machine.succeed(
          "ip netns exec vpn valkey-cli -h 192.0.2.2 client info | grep 'addr=192.0.2.1:'"
      )
      machine.succeed(
          "ip netns exec vpn valkey-cli -h 2001:db8::2 client info | grep -F 'addr=[2001:db8::1]:'"
      )
      machine.succeed(
          "ip netns exec peer valkey-cli -h 192.0.2.2 client info | grep 'addr=192.0.2.1:'"
      )
      machine.succeed(
          "ip netns exec torrent valkey-cli -h 10.100.0.1 client info | grep 'addr=10.0.1.5:'"
      )
      machine.succeed("ip netns exec tunnel valkey-cli -h 10.0.1.11 -p 53 ping | grep PONG")
      machine.succeed("conntrack -L -s 10.100.0.1 -d 10.0.1.11 | grep 'mark=1'")
      # Exercise the real native CNI port mapper on the same nft firewall.
      machine.succeed("CNI_COMMAND=ADD ${cni}")
      machine.succeed("nft list chain ip cni_hostport hostports | grep 'tcp dport 1053'")
      machine.succeed("valkey-cli -h 127.0.0.1 -p 1053 ping | grep PONG")
      machine.succeed("ip netns exec dns valkey-cli -h 10.0.1.1 -p 1053 ping | grep PONG")
      machine.succeed("ip netns exec vpn valkey-cli -h 100.64.0.1 -p 1053 ping | grep PONG")
      machine.succeed("ip netns exec immich valkey-cli -h 10.0.1.129 ping | grep PONG")
      machine.succeed("ip netns exec outline valkey-cli -h 10.0.1.133 ping | grep PONG")
      machine.succeed("valkey-cli -h 10.0.1.129 ping | grep PONG")
      # Tailnet DNS and infrastructure containers' DNS must remain reachable.
      for namespace in ["immich", "outline", "peer", "edge", "vpn"]:
          machine.succeed(f"ip netns exec {namespace} nc -z -w 1 10.0.1.11 53")
      for namespace in ["peer", "edge", "vpn", "outline"]:
          machine.fail(f"ip netns exec {namespace} nc -z -w 1 10.0.1.129 6379")
      for namespace in ["peer", "edge", "vpn", "immich"]:
          machine.fail(f"ip netns exec {namespace} nc -z -w 1 10.0.1.133 6379")
      # Reload is atomic/idempotent and leaves the intended application usable.
      machine.succeed(
          "nft -f /etc/raw-firewall.nft; ip netns exec immich valkey-cli -h 10.0.1.129 ping | grep PONG"
      )
      machine.succeed("systemctl reload polpetta-raw-firewall; systemctl reload nftables")
      machine.succeed("valkey-cli -h 127.0.0.1 -p 1053 ping | grep PONG")
      machine.succeed(
          "CNI_COMMAND=DEL ${cni}; ! nft list chain ip cni_hostport hostports | grep -q 'tcp dport 1053'"
      )
      machine.fail("ip netns exec peer nc -z -w 1 10.0.1.129 6379")
      machine.succeed("ip netns exec immich valkey-cli -h 10.0.1.129 ping | grep PONG")
      # Confirm that access came from our policy, not an unrelated network fault.
      machine.succeed(
          "nft flush chain bridge polpetta_raw forward; nft flush chain inet polpetta_raw raw_ports"
      )
      machine.succeed("ip netns exec peer valkey-cli -h 10.0.1.129 ping | grep PONG")
      machine.succeed("nft -f /etc/raw-firewall.nft")
      machine.fail("ip netns exec peer nc -z -w 1 10.0.1.129 6379")
      # Use previously unopened sockets so conntrack cannot mask a policy failure.
      machine.succeed(
          'ip netns exec immich valkey-server --port 2283 --protected-mode no --save "" --daemonize yes; ip netns exec immich valkey-server --port 2284 --protected-mode no --save "" --daemonize yes; ip netns exec torrent valkey-server --port 6881 --protected-mode no --save "" --daemonize yes; valkey-server --port 9090 --protected-mode no --save "" --daemonize yes'
      )
      machine.succeed("ip netns exec nginx nc -z -w 2 10.0.1.3 2283")
      machine.succeed("nc -z -w 2 10.0.1.3 2284")
      machine.fail("ip netns exec nginx nc -z -w 2 10.0.1.3 2284")
      for namespace in ["peer", "vpn", "uplink", "tunnel"]:
          machine.fail(f"ip netns exec {namespace} nc -z -w 2 10.0.1.3 2283")
      machine.succeed("ip netns exec immich valkey-cli -h 10.0.1.129 ping | grep PONG")
      machine.succeed("ip netns exec vpn nc -z -w 2 10.0.1.11 53")
      machine.succeed(
          "ip -n tunnel addr add 198.51.100.2/32 dev eth0; ip route add 198.51.100.2/32 dev wg0; ip netns exec tunnel nc -s 198.51.100.2 -z -w 2 10.0.1.5 6881"
      )
      machine.fail("ip netns exec uplink nc -z -w 2 10.0.1.5 6881")
      machine.succeed(
          "nc -z -w 2 127.0.0.1 9090; ip netns exec grafana nc -z -w 2 10.0.1.1 9090"
      )
      for namespace, address in [
          ("peer", "10.0.1.1"),
          ("vpn", "100.64.0.1"),
          ("uplink", "192.0.2.1"),
          ("tunnel", "10.100.0.2"),
      ]:
          machine.fail(f"ip netns exec {namespace} nc -z -w 2 {address} 9090")
      machine.succeed("systemctl reload polpetta-raw-firewall")
      # The network tests stand in for the post-Headscale traffic on tailscale0.
      machine.succeed(
          'ip netns exec nginx valkey-server --port 8443 --protected-mode no --save "" --daemonize yes; ip netns exec torrent valkey-server --port 8080 --protected-mode no --save "" --daemonize yes'
      )
      machine.fail("ip netns exec vpn nc -z -w 1 10.0.2.6 443")
      machine.succeed("nft -f /etc/raw-firewall-admin.nft")
      machine.succeed(
          "ip netns exec vpn valkey-cli -h 10.0.2.6 -p 443 client info | grep 'addr=100.64.0.7:'"
      )
      for namespace, router in [("uplink", "192.0.2.1"), ("tunnel", "10.100.0.2")]:
          machine.succeed(f"ip -n {namespace} route add 10.0.2.6/32 via {router}")
          machine.fail(f"ip netns exec {namespace} nc -z -w 1 10.0.2.6 443")
      for namespace in ["vpn", "uplink", "tunnel", "peer"]:
          machine.fail(f"ip netns exec {namespace} nc -z -w 1 10.0.1.6 8443")
          machine.fail(f"ip netns exec {namespace} nc -z -w 1 10.0.1.5 8080")
      for namespace in ["nginx", "radarr", "sonarr"]:
          machine.succeed(f"ip netns exec {namespace} nc -z -w 1 10.0.1.5 8080")
      machine.succeed("systemctl reload polpetta-raw-firewall")
      machine.fail("ip netns exec vpn nc -z -w 1 10.0.2.6 443")
      # A broken policy must prevent the engine's startup action from running.
      machine.succeed("systemctl start containerd; test -f /tmp/containerd-started")
      machine.succeed(
          "systemctl stop polpetta-raw-firewall; rm /tmp/containerd-started; mkdir -p /run/systemd/system/polpetta-raw-firewall.service.d"
      )
      machine.succeed(
          "printf '[Service]\\nExecStart=\\nExecStart=/run/current-system/sw/bin/false\\n' > /run/systemd/system/polpetta-raw-firewall.service.d/fail.conf; systemctl daemon-reload"
      )
      machine.fail("systemctl start containerd")
      machine.succeed("test ! -f /tmp/containerd-started")
    '';
}
