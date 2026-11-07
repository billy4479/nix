{ domain, ... }:
{
  # Host key of the vps, pinned so root services (the certbot cert push to
  # billy@external.<domain>) verify on first connect instead of
  # TOFU-trusting whatever answers. external.<domain> resolves to the
  # vps from every DNS view (public, lan, wg).
  programs.ssh.knownHosts = {
    "external.${domain}" = {
      extraHostNames = [ "vps-proxy" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/MZShaZ6iAAwqhK3v5oANtG6lFyoPgr7KfOWqOUqWd";
    };
  };
}
