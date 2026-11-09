const assert = require('node:assert/strict');

// Exercise the rebuilt addon with the runtime interpreter, without falling
// back to a bundled prebuild or any build-time Node.js installation.
const pty = require(process.argv[2]);
const terminal = pty.spawn(process.argv[3], ['-c', 'printf "pty-runtime-ok"'], {
  cwd: process.env.TMPDIR,
  env: { TERM: 'xterm' },
});

let output = '';
terminal.onData((data) => { output += data; });
const timeout = setTimeout(() => {
  terminal.kill();
  throw new Error('PTY child did not exit');
}, 10_000);

terminal.onExit(({ exitCode }) => {
  clearTimeout(timeout);
  assert.equal(exitCode, 0);
  assert.equal(output, 'pty-runtime-ok');
});
