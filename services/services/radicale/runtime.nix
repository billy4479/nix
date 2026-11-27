{ pkgs }:
pkgs.python3.withPackages (ps: [
  ps.authlib
  ps.bcrypt
  ps.cryptography
  ps.flask
  ps.gunicorn
  (ps.toPythonModule pkgs.radicale)
])
