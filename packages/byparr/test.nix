{ pythonEnv, runCommand }:

runCommand "byparr-playwright-driver-test" { } # sh
  ''
    ${pythonEnv}/bin/python ${./test-driver.py}
    touch "$out"
  ''
