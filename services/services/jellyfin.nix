{ config, options, pkgs, lib, ... }:
let
  name = "jellyfin";
  containerId = 10;
  # Matches nerdctl-containers' uid for this container (5000 + id by
  # default); the seeded plugin files must be owned by it so Jellyfin can
  # write its meta.json next to the dlls.
  containerUid = config.polpetta.services.jellyfin.container.uid;
  baseHDDDir = "/mnt/HDD/torrent";
  baseSSDDir = "/mnt/SSD/apps/${name}";

  # SSO-Auth plugin (https://github.com/9p4/jellyfin-plugin-sso), pinned to a
  # release zip and unpacked into the layout Jellyfin scans recursively under
  # <datadir>/plugins: plugins/SSO-Auth/<version>/*.dll. Jellyfin 12 auto-loads
  # such a manifest-free folder (no meta.json needed); the Duende dlls are the
  # plugin's bundled OIDC client libraries and must sit beside SSO-Auth.dll.
  # The zip's meta.json is dropped on purpose: the server only reads it at the
  # plugin-folder root, and a root manifest would pin targetAbi 10.11 (harmless
  # but pointless for a read-only folder the catalog never manages).
  ssoAuthPlugin = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "jellyfin-plugin-sso-auth";
    version = "4.0.0.4";

    src = pkgs.fetchurl {
      url = "https://github.com/9p4/jellyfin-plugin-sso/releases/download/v${version}/sso-authentication_${version}.zip";
      hash = "sha256-wJ8WujEFmkNN3X+BHk+WCNS0xFFMyApb8cozvuYeEQc=";
    };

    nativeBuildInputs = [ pkgs.unzip ];

    # The release zip contains the dlls (and meta.json) at its root, without a
    # wrapping directory.
    sourceRoot = ".";

    installPhase = # sh
      ''
        mkdir -p $out/plugins/SSO-Auth/${version}
        install -m 0644 \
          SSO-Auth.dll Duende.IdentityModel.dll Duende.IdentityModel.OidcClient.dll \
          $out/plugins/SSO-Auth/${version}
      '';
  };
in
{
  # Seed the SSO plugin into the rw config volume before the container
  # starts. The unit's preStart runs as root on every start, so a deploy
  # applies the plugin immediately — without needing a reboot. tmpfiles
  # cannot do this job here: rules only apply at boot (switches never run
  # them), and systemd's chase() refuses to canonicalize this volume at
  # all, because /mnt/SSD/apps/jellyfin is owned by uid 5000 and config/
  # by the container's 5010 — an "unsafe path transition" under
  # CHASE_SAFE — so any rule below /config aborts before copying. The dlls
  # are chowned to the container user because Jellyfin 12 writes meta.json
  # next to them on every start: the same write that made the previous
  # read-only store bind crash with EROFS. Reseeding on every start is
  # cheap and self-healing; version bumps land in a fresh directory while
  # the old one stays for reference.
  systemd.services."nerdctl-jellyfin".preStart = lib.mkIf (options ? nerdctl-containers) (
    lib.mkAfter # sh
      ''
        plugdir=${baseSSDDir}/config/plugins/SSO-Auth/${ssoAuthPlugin.version}
        mkdir -p "$plugdir"
        install -m 0644 \
          ${ssoAuthPlugin}/plugins/SSO-Auth/${ssoAuthPlugin.version}/*.dll \
          "$plugdir/"
        chown -R ${toString containerUid}:5000 ${baseSSDDir}/config/plugins/SSO-Auth
      ''
  );

  polpetta.services.jellyfin = {
    container = {
      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        config = {
          entrypoint = [ (lib.getExe pkgs.jellyfin) ];
          cmd = [
            "--datadir=/config"
            "--cachedir=/cache"
          ];
        };

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          intel-media-driver
          intel-vaapi-driver
          vpl-gpu-rt
        ];
      };

      id = containerId;

      # Steady-state usage is ~130MB and concurrent transcodes can spike well
      # beyond that during long viewing sessions.
      tmpfs = [ "/tmp:size=1g" ];

      volumes = [
        {
          hostPath = baseHDDDir;
          containerPath = "/media";
          readOnly = true;
        }
        {
          hostPath = "/mnt/HDD/generic";
          containerPath = "/generic-media";
          readOnly = true;
        }
        {
          hostPath = "${baseSSDDir}/config";
          containerPath = "/config";
        }
        {
          hostPath = "${baseSSDDir}/cache";
          containerPath = "/cache";
        }
      ];

      environment = {
        LIBVA_DRIVER_NAME = "iHD";
        LIBVA_DRIVER_PATH = "${pkgs.intel-media-driver}/lib/dri:${pkgs.intel-vaapi-driver}/lib/dri";
      };

      extraOptions = [
        "--device=/dev/dri:/dev/dri"
      ];
    };

    web = {
      port = 8096;
      access = "tailnet";
      nginx.extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 3600;
        send_timeout 3600;
      '';
    };
  };
}
