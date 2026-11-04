{
  pkgs,
  ruleset,
  rawUnit,
}:
pkgs.testers.runNixOSTest {
  name = "raw-port-isolation";
  # Also runnable in the development container without /dev/kvm.
  requiredFeatures.kvm = false;
  requiredFeatures.nixos-test = false;
  qemu.forceAccel = false;
  nodes.machine = {
    virtualisation.memorySize = 768;
    systemd.services.polpetta-raw-firewall = {
      inherit (rawUnit)
        serviceConfig
        reloadIfChanged
        before
        after
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
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    environment.systemPackages = [
      pkgs.nftables
      pkgs.iptables
      pkgs.valkey
      pkgs.netcat-openbsd
    ];
    environment.etc."raw-firewall.nft".source = ruleset;
  };
  testScript = # python
    ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("polpetta-raw-firewall.service")
      machine.succeed("ip link add br-test type bridge; ip link set br-test up; ip addr add 10.0.1.1/24 dev br-test")
      for name, suffix in [("immich", 3), ("outline", 24), ("peer", 21), ("edge", 131), ("redis", 129), ("outline-redis", 133), ("dns", 11)]:
          machine.succeed(f"ip netns add {name}; ip link add v-{suffix} type veth peer name eth0 netns {name}; ip link set v-{suffix} master br-test; ip link set v-{suffix} up; ip -n {name} link set lo up; ip -n {name} link set eth0 up; ip -n {name} addr add 10.0.1.{suffix}/24 dev eth0; ip -n {name} route add default via 10.0.1.1")
      machine.succeed("ip netns add vpn; ip link add vpn-host type veth peer name eth0 netns vpn; ip addr add 100.64.0.1/24 dev vpn-host; ip link set vpn-host up; ip -n vpn link set eth0 up; ip -n vpn addr add 100.64.0.7/24 dev eth0; ip -n vpn route add 10.0.1.0/24 via 100.64.0.1")
      for namespace, address in [("redis", "10.0.1.129"), ("outline-redis", "10.0.1.133")]:
          machine.succeed(f"ip netns exec {namespace} valkey-server --bind {address} --port 6379 --protected-mode no --save \"\" --daemonize yes --dir /tmp --pidfile /tmp/{namespace}.pid --logfile /tmp/{namespace}.log")
      machine.succeed("ip netns exec dns valkey-server --bind 10.0.1.11 --port 53 --protected-mode no --save \"\" --daemonize yes --dir /tmp --pidfile /tmp/dns-test.pid --logfile /tmp/dns-test.log")
      # Deliberately permissive CNI-style filter rules must not bypass our hooks.
      machine.succeed("iptables -I FORWARD 1 -j ACCEPT; nft -f /etc/raw-firewall.nft")
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
      machine.succeed("nft -f /etc/raw-firewall.nft; ip netns exec immich valkey-cli -h 10.0.1.129 ping | grep PONG")
      machine.succeed("systemctl reload polpetta-raw-firewall; systemctl reload firewall")
      machine.fail("ip netns exec peer nc -z -w 1 10.0.1.129 6379")
      machine.succeed("ip netns exec immich valkey-cli -h 10.0.1.129 ping | grep PONG")
      # Confirm that access came from our policy, not an unrelated network fault.
      machine.succeed("nft flush chain bridge polpetta_raw forward; nft flush chain inet polpetta_raw raw_ports")
      machine.succeed("ip netns exec peer valkey-cli -h 10.0.1.129 ping | grep PONG")
      machine.succeed("nft -f /etc/raw-firewall.nft")
      machine.fail("ip netns exec peer nc -z -w 1 10.0.1.129 6379")
      # A broken policy must prevent the engine's startup action from running.
      machine.succeed("systemctl start containerd; test -f /tmp/containerd-started")
      machine.succeed("systemctl stop polpetta-raw-firewall; rm /tmp/containerd-started; mkdir -p /run/systemd/system/polpetta-raw-firewall.service.d")
      machine.succeed("printf '[Service]\\nExecStart=\\nExecStart=/run/current-system/sw/bin/false\\n' > /run/systemd/system/polpetta-raw-firewall.service.d/fail.conf; systemctl daemon-reload")
      machine.fail("systemctl start containerd")
      machine.succeed("test ! -f /tmp/containerd-started")
    '';
}
