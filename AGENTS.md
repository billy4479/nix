# My Nix Flake

## What is it

In this repository lives a Nix Flake which manages 4 NixOS + home-manager systems:
- `computerone` is my main desktop PC.
- `portatilo` is my main laptop.
- `serverone` is my home server and NAS.
- `vps-proxy` is a vps box with very limited compute resources.

You can check the hostname to detect on which system you are running on.
You can ssh into any other system (as an unpriviliged user) by running `ssh <HOSTNAME>`.

## Building and validation

Deployment of each system and secret management is responsibility of the user only, do not worry about it.

To validate your changes you can use 
```sh
nix build .#nixosConfigurations.HOSTNAME.config.system.build.toplevel
```
which builds the system you specified. 

In non-server machines (i.e. `computerone` and `portatilo`) home-manager is installed standalone, therefore to build non-system changes you should use
```sh
nix build .#homeConfigurations.USERNAME@HOSTNAME.activationPackage
```

## Style

When you need to embed another language in a nix file (for example for writing shell scripts or lua configs) you should annotate which language you're using:
```nix

{
  aShellScript = # sh
    ''
      echo hi
    '';
  aLuaConfig = # lua
    ''
      function hello()
          print("hello")
      end
    '';
}
```

## Documentation

Documentation lives in the `docs` folder, consult it only if you think it might be relevant to your current task.
Make sure you keep the docs up to date.

## Running commands

If you need to run some commmand which isn't install you can fall back to using a `nix shell`.

When you ssh into a remote host you do not have root access, however you can ask the user to run a privileged command for you.
