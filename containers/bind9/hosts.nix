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
      cat <<EOF >$out
      $TTL 1H
      @       IN      SOA     localhost. root.localhost. (
                              1               ; Serial
                              3H              ; Refresh
                              1H              ; Retry
                              1W              ; Expire
                              1H )            ; Negative Cache TTL
              IN      NS      localhost.

      ; Block List
      EOF

      grep "^0.0.0.0" ${src} |
        cut -d " " -f 2 |
        tail -n +2 |
        sort |
        grep -v "s.click.aliexpress.com" |
        grep -v "click.aliexpress.com" |
        sed -r 's/(.*)/\1 CNAME ./' >>$out
    '';
}
