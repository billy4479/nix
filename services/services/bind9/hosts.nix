{
  stdenvNoCC,
  lib,
  fetchFromGitHub,
  python3,
  writeText,
  settings ? import ./blocklist.nix,
}:
let
  inherit (settings)
    feeds
    extensions
    allowlist
    blocklist
    ;
  whitelist = writeText "hosts-whitelist" (lib.concatMapStrings (domain: "${domain}\n") allowlist);
  blacklist = writeText "hosts-blacklist" (
    lib.concatMapStrings (domain: "0.0.0.0 ${domain}\n") blocklist
  );
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "bind9-hosts";
  version = "3.16.131";

  src = fetchFromGitHub {
    owner = "StevenBlack";
    repo = "hosts";
    tag = finalAttrs.version;
    hash = "sha256-Qc14YoLPrKiZyEeD9w9ccPGGmdLBHC7cYUfw+ynYAIc=";
  };

  nativeBuildInputs = [ (python3.withPackages (ps: [ ps.requests ])) ];
  dontConfigure = true;

  buildPhase = # sh
    ''
      runHook preBuild
      feeds=(${lib.escapeShellArgs (if feeds == null then [ ] else feeds)})
      extensions=(${lib.escapeShellArgs extensions})
      if ${lib.boolToString (feeds != null)}; then
        mv data all-feeds
        mkdir data
        for feed in "''${feeds[@]}"; do
          if [[ "$feed" == */* || ! -f "all-feeds/$feed/hosts" ]]; then
            echo "Unknown StevenBlack base feed: $feed" >&2
            exit 1
          fi
          cp -r "all-feeds/$feed" data/
        done
      fi
      for extension in "''${extensions[@]}"; do
        if [[ "$extension" == */* || ! -d "extensions/$extension" ]]; then
          echo "Unknown StevenBlack extension: $extension" >&2
          exit 1
        fi
      done

      options=(${lib.optionalString (feeds == [ ]) "--nounifiedhosts"})
      if ${lib.boolToString (extensions != [ ])}; then
        options+=(--extensions "''${extensions[@]}")
      fi
      python3 updateHostsFile.py --auto --noupdate --nogendata --skipstatichosts \
        --whitelist ${whitelist} --blacklist ${blacklist} --output generated "''${options[@]}"
      runHook postBuild
    '';

  installPhase = # sh
    ''
      runHook preInstall
      cat >"$out" <<'EOF'
      $TTL 1H
      @ IN SOA localhost. root.localhost. (
        1  ; Serial
        1H ; Refresh
        1H ; Retry
        1W ; Expire
        1H ; Negative Cache TTL
      )
        IN NS localhost.

      ; Block List
      EOF

      awk '$1 == "0.0.0.0" && NF >= 2 && $2 != "0.0.0.0" && $2 !~ /^#/ { print $2 " CNAME ." }' generated/hosts |
        LC_ALL=C sort -u >>"$out"
      runHook postInstall
    '';
})
