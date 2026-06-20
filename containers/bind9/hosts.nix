{ stdenvNoCC, fetchurl, ... }:
stdenvNoCC.mkDerivation rec {
  pname = "bind9-hosts";
  version = "1.0.0";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/StevenBlack/hosts/f0c1e878685f647bac77f6ed81980379318ee7c3/hosts";
    hash = "sha256-fySXABWhkH15oyHAaBRlobmF2j5RlpxlTSWTC9sBN98=";
  };

  dontUnpack = true;

  buildPhase = # sh
    ''
      echo '$TTL 1H' >$out
      cat <<EOF >>$out
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
