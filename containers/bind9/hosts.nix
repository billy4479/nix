{ stdenvNoCC, fetchurl, ... }:
stdenvNoCC.mkDerivation rec {
  pname = "bind9-hosts";
  version = "1.0.0";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/StevenBlack/hosts/2b274d002ccbb49407f1b43091417b041b947d28/hosts";
    hash = "sha256-dmqKd8m1JFzTDXjeZUYnbvZNX/xqMiXYFRJFveq7Nlc=";
  };

  dontUnpack = true;

  buildPhase = # sh
    ''
      grep "^0.0.0.0" ${src} |
        cut -d " " -f 2 |
        tail -n +2 |
        sort |
        grep -v "s.click.aliexpress.com" |
        grep -v "click.aliexpress.com" |
        sed -r 's/(.*)/zone "\1" { type master; file "\/etc\/bind\/sinkhole.zone"; };/' >$out
    '';
}
