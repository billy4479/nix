{ extraConfig, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/${extraConfig.hostname}.yaml;

    validateSopsFiles = false;

    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };

  environment.sessionVariables = {
    SOPS_AGE_KEY_FILE = "/var/lib/sops-nix/key.txt";
  };
}
