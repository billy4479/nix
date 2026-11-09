# nix-packages

This is my collection of nix packages.

Since I'm the only maintainer keep the code complexity low.

Make sure the closure only contains what's actually needed.

Always check if upstream nixpkgs already contains a certain package before creating a new package. If the package already exists, notify the user, you can take inspiration from the upstream package.

Always consult the nixpkgs documentation on how to package a program written in a certain programming language, framework, toolkit, etc.

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