{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

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
makeContainer {
  inherit name;
  image = "localhost/stirling-pdf:latest";
  imageFile = pkgs.dockerTools.buildImage {

    inherit name;
    tag = "latest";

    copyToRoot = with pkgs; [
      stirling-pdf

      # https://docs.stirlingpdf.com/Installation/Unix%20Installation#step-3-install-additional-software
      # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/web-apps/stirling-pdf.nix
      which

      libreoffice-fresh
      tess
      ghostscript_headless
      pngquant
      ocrmypdf
      unoconv
      unpaper
      poppler-utils

      (python3.withPackages (p: [
        p.opencv-python-headless
        # FIXME: seems broken in the new nix version
        # p.weasyprint

        p.pillow
        p.pdf2image
      ]))

      # https://github.com/Stirling-Tools/Stirling-PDF/blob/main/Dockerfile
      calibre
      ffmpeg
      qpdf
    ];

    # TODO: fix OCR

    # extraCommands = # sh
    #   ''
    #     mkdir -p /usr/share
    #     ln -s ${tess}/share/tessdata /usr/share/tessdata
    #   '';

    config = {
      EntryPoint = [ "Stirling-PDF" ];
    };
  };

  ip = "10.0.1.12";

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
}
