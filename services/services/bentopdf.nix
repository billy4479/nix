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

      entrypoint = [
        "${pkgs.darkhttpd}/bin/darkhttpd"
        "${pkgs.bentopdf}"
        "--port"
        "8080"
        "--addr"
        "0.0.0.0"
      ];
    };

    web = {
      port = 8080;
      access = "tailnet";
    };
  };
}
