{
  pkgs,
  lib,
  config,
  ...
}:
let
  wantedLangs = [
    {
      name = "it";
      splHash = "sha256:04vlmri8fsza38w7pvkslyi3qrlzyb1c3f0a1iwm6vc37s8361yq";
      sugHash = "sha256:0jnf4hkpr4hjwpc8yl9l5dddah6qs3sg9ym8fmmr4w4jlxhigfz0";
    }
    {
      name = "en";
      splHash = "sha256:0w1h9lw2c52is553r8yh5qzyc9dbbraa57w9q0r9v8xn974vvjpy";
      sugHash = "sha256:1v1jr4rsjaxaq8bmvi92c93p4b14x2y1z95zl7bjybaqcmhmwvjv";
    }
    {
      name = "es";
      splHash = "sha256:1qvv6sp4d25p1542vk0xf6argimlss9c7yh7y8dsby2wjan3fdln";
      sugHash = "sha256:0v5x05438r8aym2lclvndmjbshsfzzxjhqq80pljlg35m9w383z7";
    }
  ];

  mirror = "https://vim.mirror.garr.it";
  dir = "/pub/vim/runtime/spell/";

  allData = builtins.foldl' (
    a: x:
    a
    ++ [
      {
        finalFileName = "${x.name}.utf-8.spl";
        url = "${mirror}${dir}${x.name}.utf-8.spl";
        sha256 = x.splHash;
      }
      {
        finalFileName = "${x.name}.utf-8.sug";
        url = "${mirror}${dir}${x.name}.utf-8.sug";
        sha256 = x.sugHash;
      }
    ]
  ) [ ] wantedLangs;

  fetchedPaths = map (
    x:
    (
      {
        fetchedPath = builtins.fetchurl (builtins.removeAttrs x [ "finalFileName" ]);
      }
      // x
    )
  ) allData;

  spellsDrv = pkgs.stdenvNoCC.mkDerivation {
    pname = "vim-spells";
    version = pkgs.vim.version;

    dontBuild = true;
    dontUnpack = true;

    installPhase = # sh
      ''
        mkdir -p $out
      ''
      + lib.concatStringsSep "\n" (
        map (x: "cp -v ${x.fetchedPath} $out/${x.finalFileName}") fetchedPaths
      );
  };
in
{
  home.file."${config.xdg.configHome}/nvim/spell".source = spellsDrv;
}
