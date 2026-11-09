{
  nodejs-slim,
  openchamber-web,
  runCommand,
  stdenvNoCC,
}:

runCommand "openchamber-web-pty-test" { } # sh
  ''
    ${nodejs-slim}/bin/node ${./test.cjs} \
      ${openchamber-web}/lib/openchamber-web/node_modules/node-pty \
      ${stdenvNoCC.shell}
    touch "$out"
  ''
