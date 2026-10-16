# BentoPDF is fully client-side: the container only serves its static files,
# all PDF processing happens in the browser.
{ pkgs, ... }:
let
  name = "bentopdf";
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

          pathsToLink = [
            "/bin"
            "/share/bentopdf"
          ];
          paths = [
            pkgs.darkhttpd
            (pkgs.runCommand "bentopdf-webroot" { } ''
              mkdir -p $out/share/bentopdf
              cp -r ${pkgs.bentopdf}/. $out/share/bentopdf/
            '')
          ];
        };

        config = {
          Entrypoint = [
            "darkhttpd"
            "/share/bentopdf"
            "--port"
            "8080"
            "--addr"
            "0.0.0.0"
          ];
        };
      };
    };

    web = {
      port = 8080;
      access = "tailnet";
    };
  };
}
