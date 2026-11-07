# WireGuard tunnel endpoint on the vps: serverone initiates from behind its
# NAT, the vps only listens. Public traffic is DNAT'd into the tunnel with
# the real source address preserved — no SNAT — so replies must be
# policy-routed back into the tunnel on serverone (see
# system/hosts/serverone/wireguard.nix).
{
  config,
  lib,
  pkgs,
  flakeInputs,
  ...
}:
let
  # serverone's wireguard public key from the secrets repo, same pattern as
  # the authorized ssh keys. The trailing newline is stripped: wg rejects
  # keys with trailing whitespace.
  serveronePublicKey = lib.removeSuffix "\n" (
    builtins.readFile "${flakeInputs.secrets-repo}/public_keys/wireguard/serverone.pub"
  );

  # The vps public IP (statically assigned by the provider). DNAT is
  # anchored on it so only traffic addressed to the vps is forwarded, never
  # anything the tunnel merely transits.
  publicIp = "87.106.25.93";

  # Plain HTTP for the web edge: the DNAT goes to nginx's plain :80 listener
  # (10.0.1.6 is the nginx container, stable edge infrastructure like the vps
  # itself). The :81 listener expects a proxy_protocol header that DNAT does
  # not write, and none is needed here — the real client address is the
  # packet source already.
  webForward = {
    proto = "tcp";
    port = 80;
    target = "10.0.1.6";
    targetPort = 80;
  };

  # HTTP/3: QUIC arrives as udp/443 and terminates on the same nginx vhosts
  # as tcp/443. It bypasses the SNI demuxer by design (nginx stream cannot
  # SNI-demux UDP, and nothing needs it: derp never speaks h3, so no QUIC
  # for derp.<domain> ever arrives).
  http3Forward = {
    proto = "udp";
    port = 443;
    target = "10.0.1.6";
    targetPort = 443;
  };

  edgeForwards = config.polpetta.generated.dnatForwards ++ [
    webForward
    http3Forward
  ];
in
{
  systemd.services.edge-forwarding = import ./edge-forwarding.nix {
    inherit lib pkgs publicIp;
    forwards = edgeForwards;
  };

  sops.secrets.wireguard-key = {
    # The unit reads the key once at start; without a restart a rotated key
    # would leave the interface authenticated with the stale key and the
    # tunnel would silently break.
    restartUnits = [ "wireguard-wg0.service" ];
  };

  # Public traffic is DNAT'd into the tunnel (FORWARD, not INPUT); without
  # forwarding the vps is a dead end.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall = {
    # Un-translated replies arrive from the tunnel carrying the vps's own
    # public address as source (conntrack reverses the DNAT before the route
    # check); strict reverse-path filtering would drop them as martians.
    checkReversePath = "loose";

    # INPUT sees only what terminates locally on the vps: the SNI demuxer,
    # the STUN server, ssh (opened by the openssh module) and the wireguard
    # port itself. DNAT'd traffic is forwarded and never traverses INPUT,
    # which is what keeps the edge exposure bounded to the forward list.
    allowedTCPPorts = [ 443 ];
    allowedUDPPorts = [
      3478
      51820
    ];
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    mtu = 1420;
    privateKeyFile = config.sops.secrets.wireguard-key.path;
    peers = [
      {
        publicKey = serveronePublicKey;
        # The tunnel subnet plus serverone's container bridge: edge DNAT
        # rewrites public ports straight to container IPs, so the tunnel must
        # carry and route those destinations.
        allowedIPs = [
          "10.100.0.2/32"
          "10.0.1.0/24"
        ];
        # serverone initiates and roams (its WAN IP may change): no endpoint,
        # no keepalive — the peer address is learned from authenticated
        # packets.
      }
    ];
  };
}
