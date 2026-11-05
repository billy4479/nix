{ pkgs }:
let
  inherit (pkgs) lib;
  publicIp = "87.106.25.93";
  forward = port: targetPort: {
    proto = "tcp";
    inherit port targetPort;
    target = "10.0.1.6";
  };
  service =
    forwards:
    import ../system/hosts/vps-proxy/edge-forwarding.nix {
      inherit
        lib
        pkgs
        publicIp
        forwards
        ;
    };
in
pkgs.testers.runNixOSTest {
  name = "edge-forwarding-lifecycle";
  requiredFeatures.kvm = false;
  requiredFeatures.nixos-test = false;
  qemu.forceAccel = false;
  nodes.machine = {
    virtualisation.memorySize = 768;
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    networking.firewall.checkReversePath = "loose";
    # Activation retriggers udev. Keep DHCP from reconfiguring the fixture's
    # manually addressed interfaces during the generation switches.
    networking.dhcpcd.denyInterfaces = [
      "edge-public"
      "wan"
      "wg0"
    ];
    environment.systemPackages = [
      pkgs.iptables
      pkgs.netcat-openbsd
    ];
    # The test exercises forwarding and lifecycle, not tunnel encryption.
    systemd.services.wireguard-wg0 = {
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "true";
    };
    systemd.services.edge-forwarding = service [
      (forward 8080 9000)
      (forward 8081 9000)
    ];
    specialisation.changed.configuration.systemd.services.edge-forwarding = lib.mkForce (service [
      (forward 8081 9001)
    ]);
    # Models rolling back to a generation that has no edge-forwarding unit.
    specialisation.legacy.configuration.systemd.services.edge-forwarding.enable = lib.mkForce false;
  };
  testScript = # python
    ''
      start_all()
      machine.wait_for_unit("edge-forwarding.service")
      base = machine.succeed("readlink -f /run/current-system").strip()
      machine.succeed("ip link add edge-public type dummy; ip addr add ${publicIp}/32 dev edge-public; ip link set edge-public up")
      for name, host, host_ip, peer_ip in [
          ("client", "wan", "198.51.100.1", "198.51.100.2"),
          ("backend", "wg0", "10.0.1.1", "10.0.1.6"),
      ]:
          machine.succeed(f"ip netns add {name}; ip link add {host} type veth peer name eth0 netns {name}; ip addr add {host_ip}/24 dev {host}; ip link set {host} up; ip -n {name} link set lo up; ip -n {name} addr add {peer_ip}/24 dev eth0; ip -n {name} link set eth0 up; ip -n {name} route add default via {host_ip}")
      machine.succeed("ip link set wg0 mtu 1420")
      # Keep an unrelated NAT rule to catch accidental flushing of shared chains.
      machine.succeed("iptables -t nat -A PREROUTING -p tcp --dport 9999 -j ACCEPT")
      machine.succeed("ip netns exec backend nc -nvlk 9000 >/tmp/backend-9000.log 2>&1 &")
      machine.succeed("ip netns exec backend nc -nvlk 9001 >/tmp/backend-9001.log 2>&1 &")

      def connect(port, succeeds=True):
          command = f"ip netns exec client nc -z -w 5 ${publicIp} {port}"
          (machine.succeed if succeeds else machine.fail)(command)

      def rule_count():
          return int(machine.succeed("iptables -t nat -S PREROUTING | grep -c -- '-j POLPETTA-EDGE'").strip())

      with subtest("forwards survive firewall reload and unit restarts without duplication"):
          connect(8080)
          connect(8081)
          machine.succeed("systemctl reload firewall")
          connect(8080)
          connect(8081)
          machine.succeed("systemctl restart edge-forwarding")
          connect(8080)
          assert rule_count() == 1
          machine.wait_until_succeeds("grep 198.51.100.2 /tmp/backend-9000.log")

      with subtest("switch removes a port and replaces the remaining destination"):
          machine.succeed(f"{base}/specialisation/changed/bin/switch-to-configuration test")
          machine.wait_for_unit("edge-forwarding.service")
          rules = machine.succeed("iptables -t nat -S POLPETTA-EDGE")
          assert "9000" not in rules, rules
          assert "10.0.1.6:9001" in rules, rules
          assert rule_count() == 1
          machine.succeed("ip netns exec backend nc -z -w 1 127.0.0.1 9001")
          connect(8080, succeeds=False)
          connect(8081)
          machine.succeed("iptables -t nat -C PREROUTING -p tcp --dport 9999 -j ACCEPT")

      with subtest("removing the unit tears down NAT and MSS rules"):
          machine.succeed(f"{base}/specialisation/legacy/bin/switch-to-configuration test")
          machine.fail("iptables -t nat -S POLPETTA-EDGE")
          machine.fail("iptables -t nat -S PREROUTING | grep POLPETTA-EDGE")
          machine.fail("iptables -t mangle -S FORWARD | grep TCPMSS")
          connect(8081, succeeds=False)
          machine.succeed("iptables -t nat -C PREROUTING -p tcp --dport 9999 -j ACCEPT")
    '';
}
