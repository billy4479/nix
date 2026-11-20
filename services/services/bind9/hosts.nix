{ stdenvNoCC, fetchurl, ... }:
stdenvNoCC.mkDerivation rec {
  pname = "bind9-hosts";
  version = "1.0.0";

  # To use a custom StevenBlack build, see docs/BIND9-BLOCKLIST.md.
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

      awk '$1 == "0.0.0.0" && NF >= 2 && $2 != "0.0.0.0" && $2 !~ /^#/ { print $2 }' ${src} |
        sort |
        awk '$0 !~ /(^|\.)click\.aliexpress\.com$/ { print $0 " CNAME ." }' >>$out
    '';
}
