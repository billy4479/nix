# Remove once nerdctl natively discovers CNI nftables port allocations.
final: prev: {
  nerdctl =
    (prev.nerdctl.override (old: {
      extraPackages = (old.extraPackages or [ ]) ++ [ final.nftables ];
    })).overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [ ./nerdctl-nftables.patch ];
        postPatch = (old.postPatch or "") + ''
          cp ${./nerdctl-nftports_linux.go} pkg/portutil/cni_nftports_linux.go
        '';
      });
}
