{ pkgs, ... }:
let
  name = "stirling-pdf";
  baseDir = "/mnt/SSD/apps/${name}";
  tess = (
    pkgs.tesseract.overrideAttrs {
      languages = [
        "eng"
        "ita"
      ];
    }
  );
in
{
  polpetta.services.${name} = {
    container = {
      id = 12;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = pkgs.buildEnv {
          name = "image-root";

          pathsToLink = [ "/bin" ];
          paths = with pkgs; [
            stirling-pdf

            # https://docs.stirlingpdf.com/Installation/Unix%20Installation#step-3-install-additional-software
            # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/web-apps/stirling-pdf.nix
            which

            libreoffice-stable
            tess
            ghostscript_headless
            pngquant
            ocrmypdf
            unoconv
            unpaper
            poppler-utils

            (python3.withPackages (p: [
              p.opencv-python-headless
              p.weasyprint

              p.pillow
              p.pdf2image
            ]))

            # https://github.com/Stirling-Tools/Stirling-PDF/blob/main/Dockerfile
            calibre
            ffmpeg
            qpdf
          ];
        };

        # TODO: fix OCR

        config = {
          EntryPoint = [ "Stirling-PDF" ];
        };
      };

      # Conversions spike tmp usage (libreoffice/poppler/JVM temp files).
      tmpfs = [ "/tmp:size=512m" ];

      environment = {
        DISABLE_ADDITIONAL_FEATURES = "true";
        INSTALL_BOOK_AND_ADVANCED_HTML_OPS = "true";
        DISABLE_PIXEL = "true";
        LANGS = "en_US";
      };

      volumes = [
        # { hostPath = "${baseDir}/tessdata"; containerPath = "/usr/share/tessdata"; }
        {
          hostPath = "${baseDir}/config";
          containerPath = "/configs";
        }
        {
          hostPath = "${baseDir}/customFiles";
          containerPath = "/customFiles";
        }
        {
          hostPath = "${baseDir}/logs";
          containerPath = "/logs";
        }
        {
          hostPath = "${baseDir}/pipeline";
          containerPath = "/pipeline";
        }
      ];
    };

    web = {
      port = 8080;
      access = "tailnet";
      nginx.extraConfig = ''
        client_max_body_size 500M;
        proxy_request_buffering off;
        proxy_read_timeout 3600;
        send_timeout 3600;
      '';
    };
  };
}
