desktop:
if desktop == "kde" then
  ./kde.nix
else if desktop == "qtile" then
  ./qtile.nix
else
  throw "desktop ${desktop} is not supported"
