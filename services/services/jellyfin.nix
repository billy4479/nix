{ pkgs, lib, ... }:
let
  name = "jellyfin";
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

      id = 10;

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
        # Nested read-only bind inside the rw /config volume: the plugin dlls
        # come from the nix store while /config stays Jellyfin's own config
        # volume (its plugin settings land in /config/plugins/configurations).
        "-v ${ssoAuthPlugin}/plugins/SSO-Auth:/config/plugins/SSO-Auth:ro"
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
