import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { once } from "node:events";
import {
  mkdtemp,
  mkdir,
  readFile,
  writeFile,
  symlink,
  rm,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { trustedWorkspace, withDirenv } from "./extensions/operations.ts";

async function scratch(t) {
  const directory = await mkdtemp(path.join(tmpdir(), "pi-container-test-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

test("project trust checks lexical and real boundaries, including worktrees", async (t) => {
  const root = await scratch(t);
  const roots = { nix: path.join(root, "nix"), code: path.join(root, "code") };
  for (const relative of [
    "nix",
    "code/repo/worktree",
    "outside",
    "nix-other",
  ]) {
    await mkdir(path.join(root, relative), { recursive: true });
  }
  assert.ok(trustedWorkspace(roots.nix, roots));
  assert.ok(trustedWorkspace(path.join(roots.code, "repo/worktree"), roots));
  assert.ok(!trustedWorkspace(roots.code, roots));
  assert.ok(!trustedWorkspace(path.join(root, "nix-other"), roots));
  await symlink(path.join(root, "outside"), path.join(roots.code, "escape"));
  assert.ok(!trustedWorkspace(path.join(roots.code, "escape"), roots));
  assert.ok(
    !trustedWorkspace(path.join(roots.code, "repo/../../outside"), roots),
  );
  assert.ok(!trustedWorkspace(path.join(root, "missing"), roots));
});

test("direnv wraps native operations without changing cancellation, env or timeout", async () => {
  const signal = new AbortController().signal;
  const options = {
    signal,
    timeout: 3,
    env: { SENTINEL: "value" },
    onData() {},
  };
  let calls = 0;
  const local = {
    async exec(command, cwd, forwarded) {
      calls++;
      assert.equal(cwd, "/a project's directory");
      assert.equal(forwarded, options);
      assert.ok(
        command.startsWith(
          "exec '/bin/direnv' exec '/a project'\\''s directory' ",
        ),
      );
      assert.ok(command.includes("3>&1 4>&2 >"));
      return { exitCode: 7 };
    },
  };
  assert.deepEqual(
    await withDirenv(local).exec(
      "printf '%s' \"$SENTINEL\"",
      "/a project's directory",
      options,
    ),
    { exitCode: 7 },
  );
  assert.equal(calls, 1);
});

test("real direnv exports, unsets, blocks unapproved files, and isolates project environments", async (t) => {
  const root = await scratch(t);
  const home = path.join(root, "home");
  await mkdir(home);
  await mkdir(path.join(home, "config/direnv"), { recursive: true });
  await writeFile(
    path.join(home, "config/direnv/direnv.toml"),
    "[global]\nstrict_env = true\n",
  );
  for (const [name, value] of [
    ["one", "first"],
    ["two", "second"],
  ]) {
    const cwd = path.join(root, name);
    await mkdir(cwd);
    await writeFile(
      path.join(cwd, ".envrc"),
      `echo SETUP_STDOUT\necho SETUP_STDERR >&2\nexport PROJECT_VALUE=${value}\nunset REMOVE_ME\n`,
    );
  }
  // A native backend for exercising the wrapper outside the container's /bin.
  const local = {
    exec(command, cwd, options) {
      return new Promise((resolve, reject) => {
        const child = spawn(process.env.TEST_BASH, ["-c", command], {
          cwd,
          signal: options.signal,
          env: {
            ...process.env,
            HOME: home,
            XDG_DATA_HOME: path.join(home, "data"),
            XDG_CONFIG_HOME: path.join(home, "config"),
            ...options.env,
          },
        });
        child.stdout.on("data", options.onData);
        child.stderr.on("data", options.onData);
        child.on("error", reject);
        child.on("close", (code) => resolve({ exitCode: code }));
      });
    },
  };
  const wrapped = withDirenv(local, {
    direnv: process.env.TEST_DIRENV,
    bash: process.env.TEST_BASH,
  });
  const exec = async (cwd, command) => {
    let output = "";
    const result = await wrapped.exec(command, cwd, {
      env: { REMOVE_ME: "inherited" },
      onData: (data) => {
        output += data.toString();
      },
    });
    return { ...result, output };
  };
  let result = await exec(path.join(root, "one"), "echo MUST_NOT_EXECUTE");
  assert.notEqual(result.exitCode, 0);
  assert.ok(!result.output.includes("MUST_NOT_EXECUTE"));
  assert.match(result.output, /direnv:.*blocked/);
  for (const name of ["one", "two"]) {
    const result = await local.exec(
      `"${process.env.TEST_DIRENV}" allow .`,
      path.join(root, name),
      { onData() {} },
    );
    assert.equal(result.exitCode, 0);
  }
  const results = await Promise.all(
    ["one", "two"].map((name) =>
      exec(
        path.join(root, name),
        'printf \'RESULT:%s:%s\' "$PROJECT_VALUE" "${REMOVE_ME-unset}"',
      ),
    ),
  );
  assert.equal(results[0].output, "RESULT:first:unset");
  assert.equal(results[1].output, "RESULT:second:unset");
  result = await exec(
    path.join(root, "one"),
    "printf COMMAND_ERROR >&2; exit 13",
  );
  assert.equal(result.exitCode, 13);
  assert.equal(result.output, "COMMAND_ERROR");
  result = await exec(path.join(root, "one"), "printf COMMAND_STDERR >&2");
  assert.equal(result.output, "COMMAND_STDERR");
  result = await exec(root, "printf 'RESULT:%s' \"${PROJECT_VALUE-unset}\"");
  assert.match(result.output, /RESULT:unset/);
  result = await exec(path.join(root, "one"), "exit 13");
  assert.equal(result.exitCode, 13);
  assert.equal(result.output, "");
  await writeFile(
    path.join(root, "one/.envrc"),
    "echo SETUP_FAILURE >&2\nreturn 1\n",
  );
  assert.equal(
    (
      await local.exec(
        `"${process.env.TEST_DIRENV}" allow .`,
        path.join(root, "one"),
        { onData() {} },
      )
    ).exitCode,
    0,
  );
  result = await exec(path.join(root, "one"), "echo MUST_NOT_EXECUTE");
  assert.notEqual(result.exitCode, 0);
  assert.match(result.output, /SETUP_FAILURE/);
  assert.ok(!result.output.includes("MUST_NOT_EXECUTE"));
});

test(
  "packaged extensions load in real Pi RPC; reload retains history and picks up skills/context",
  { timeout: 60000 },
  async (t) => {
    const root = await scratch(t);
    const profile = path.join(root, "profile");
    await mkdir(profile);
    await mkdir(path.join(root, "skills/example"), { recursive: true });
    const skill = path.join(root, "skills/example/SKILL.md");
    await writeFile(
      skill,
      "---\nname: example\ndescription: First skill description\n---\nFirst body\n",
    );
    const legacy = path.join(root, ".agents/skills/example");
    await mkdir(legacy, { recursive: true });
    await writeFile(
      path.join(legacy, "SKILL.md"),
      "---\nname: example\ndescription: Stale trial copy\n---\nOld body\n",
    );
    const migration = spawnSync(
      "python3",
      [
        "-B",
        "-c",
        "from pathlib import Path; from setup import share_legacy_skills; import sys; share_legacy_skills(Path(sys.argv[1]), Path(sys.argv[1]))",
        root,
      ],
      { cwd: path.dirname(fileURLToPath(import.meta.url)), encoding: "utf8" },
    );
    assert.equal(migration.status, 0, migration.stderr);
    await writeFile(path.join(profile, "AGENTS.md"), "FIRST_CONTEXT\n");
    const extensionRoot = process.env.TEST_EXTENSIONS;
    // A command probes context without making a model request.
    const probe = path.join(root, "probe.ts");
    await writeFile(
      probe,
      `import {registerAskUserQuestionTool} from ${JSON.stringify(path.join(extensionRoot, "rpiv-ask-user-question/ask-user-question.ts"))};
  import {createLocalBashOperations, loadSkills} from "@earendil-works/pi-coding-agent";
  import {withDirenv} from ${JSON.stringify(path.join(extensionRoot, "workspace/operations.ts"))};
  export default function(pi) {
    pi.registerCommand("skill-diagnostics", {handler: (_args, ctx) => {
      const result = loadSkills({cwd: ctx.cwd, agentDir: process.env.PI_CODING_AGENT_DIR,
        skillPaths: [ctx.cwd + "/.agents/skills", ctx.cwd + "/skills"], includeDefaults: true});
      ctx.ui.notify("SKILL_DIAGNOSTICS:" + JSON.stringify(result.diagnostics), "info");
    }});
    pi.registerCommand("native-probe", {handler: async (args, ctx) => {
      const operations = withDirenv(createLocalBashOperations({shellPath: process.env.TEST_BASH}), {
        direnv: process.env.TEST_DIRENV, bash: process.env.TEST_BASH,
      });
      const controller = new AbortController();
      let streamed = "";
      try {
        await operations.exec('echo STREAMED; "' + process.env.TEST_SLEEP + '" 30', ctx.cwd, {
          signal: controller.signal, timeout: args === "timeout" ? 0.05 : undefined,
          onData(data) { streamed += data.toString(); if (args === "cancel" && streamed.includes("STREAMED")) controller.abort(); },
        });
        ctx.ui.notify("BACKEND_UNEXPECTED_SUCCESS", "error");
      } catch (error) { ctx.ui.notify("BACKEND:" + args + ":" + error.message + ":" + streamed, "info"); }
    }});
    let questionTool;
    registerAskUserQuestionTool({...pi, registerTool(tool) { questionTool = tool; }});
    pi.registerCommand("ask-probe", {handler: async (args, ctx) => {
      const result = await questionTool.execute("test-question", {questions: [{
        question: "Choose a scope", header: "Scope", multiSelect: args === "multi",
        options: [{label: "First", description: "First option"}, {label: "Second", description: "Second option"}]
      }]}, undefined, undefined, ctx);
      ctx.ui.notify("ASK_RESULT:" + JSON.stringify(result), "info");
    }});
    pi.registerCommand("probe", {handler: (_args, ctx) => ctx.ui.notify(ctx.getSystemPrompt(), "info")});
    pi.registerCommand("record", {handler: () => pi.appendEntry("test-history", {preserved: true})});
  }`,
    );
    await writeFile(
      path.join(profile, "settings.json"),
      JSON.stringify({
        extensions: [
          "workspace",
          "rpiv-ask-user-question",
          "t3code-reload",
          "free-provider",
        ].map((name) => path.join(extensionRoot, name, "index.ts")),
        skills: [path.join(root, "skills")],
      }),
    );
    const child = spawn(
      process.env.TEST_PI,
      ["--mode", "rpc", "--offline", "--no-mcp", "--no-approve", "-e", probe],
      {
        cwd: root,
        env: {
          ...process.env,
          HOME: root,
          PI_CODING_AGENT_DIR: profile,
          PI_TELEMETRY: "0",
          PI_OFFLINE: "1",
        },
        stdio: ["pipe", "pipe", "pipe"],
      },
    );
    const closed = once(child, "close");
    t.after(async () => {
      child.stdin.end();
      child.kill();
      await closed;
    });
    const pending = new Map();
    const notices = [];
    const errors = [];
    const dialogAnswers = [];
    let buffer = "";
    let stderr = "";
    let nextId = 0;
    child.stderr.on("data", (data) => {
      stderr += data;
    });
    child.stdout.on("data", (chunk) => {
      buffer += chunk;
      let newline;
      while ((newline = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        if (!line.trim()) continue;
        const message = JSON.parse(line);
        if (message.type === "extension_error") errors.push(message);
        if (message.method === "notify") notices.push(message.message);
        if (
          message.type === "extension_ui_request" &&
          ["select", "input"].includes(message.method)
        ) {
          const answer = dialogAnswers.shift();
          assert.ok(answer, `Unexpected dialog: ${JSON.stringify(message)}`);
          assert.equal(message.method, answer.method);
          const value =
            answer.option === undefined
              ? answer.value
              : message.options[answer.option];
          child.stdin.write(
            JSON.stringify({
              type: "extension_ui_response",
              id: message.id,
              ...(answer.cancelled ? { cancelled: true } : { value }),
            }) + "\n",
          );
        }
        if (message.type === "response" && pending.has(message.id)) {
          const { resolve, reject, timeout } = pending.get(message.id);
          clearTimeout(timeout);
          pending.delete(message.id);
          message.success
            ? resolve(message.data)
            : reject(new Error(message.error));
        }
      }
    });
    const request = (type, fields = {}) =>
      new Promise((resolve, reject) => {
        const id = String(++nextId);
        const timeout = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`RPC timeout: ${stderr}`));
        }, 15000);
        pending.set(id, { resolve, reject, timeout });
        child.stdin.write(JSON.stringify({ id, type, ...fields }) + "\n");
      });
    const commands = await request("get_commands");
    for (const name of ["clinefree", "zenfree"]) {
      assert.ok(
        commands.commands.some((command) => command.name === name),
        stderr,
      );
    }
    await request("prompt", { message: "/skill-diagnostics" });
    assert.ok(
      notices.includes("SKILL_DIAGNOSTICS:[]"),
      JSON.stringify(notices),
    );
    assert.ok(
      commands.commands.some((command) => command.name === "t3-reload"),
      stderr,
    );
    assert.ok(
      commands.commands.some((command) => command.name === "skill:example"),
      JSON.stringify(commands),
    );
    await request("prompt", { message: "/record" });
    const before = await request("get_entries");
    await request("prompt", { message: "/probe" });
    assert.ok(notices.some((message) => message.includes("FIRST_CONTEXT")));
    // Atomic replacement models both a host editor and future Syncthing updates.
    const replacement = path.join(profile, "new-context");
    await writeFile(replacement, "SECOND_CONTEXT\n");
    const { rename } = await import("node:fs/promises");
    await rename(replacement, path.join(profile, "AGENTS.md"));
    await writeFile(
      skill,
      "---\nname: example\ndescription: Updated skill description\n---\nUpdated body\n",
    );
    for (let count = 0; count < 2; count++) {
      await request("prompt", { message: "/t3-reload" });
      await request("prompt", { message: "/probe" });
    }
    assert.ok(notices.some((message) => message.includes("SECOND_CONTEXT")));
    assert.equal(
      notices.filter((message) => message === "Pi runtime reloaded.").length,
      2,
    );
    assert.deepEqual(await request("get_entries"), before);
    const ask = async (args, responses) => {
      dialogAnswers.push(...responses);
      await request("prompt", { message: `/ask-probe ${args}` });
      const result = notices
        .filter((message) => message.startsWith("ASK_RESULT:"))
        .at(-1);
      assert.ok(result);
      assert.equal(dialogAnswers.length, 0);
      return JSON.parse(result.slice("ASK_RESULT:".length));
    };
    assert.match(
      (await ask("single", [{ method: "select", option: 0 }])).content[0].text,
      /First/,
    );
    assert.match(
      (await ask("multi", [{ method: "input", value: "1,2" }])).content[0].text,
      /First.*Second/,
    );
    assert.match(
      (
        await ask("custom", [
          { method: "select", option: 2 },
          { method: "input", value: "My custom answer" },
        ])
      ).content[0].text,
      /My custom answer/,
    );
    assert.equal(
      (await ask("cancel", [{ method: "select", cancelled: true }])).details
        .cancelled,
      true,
    );
    await request("prompt", { message: "/native-probe cancel" });
    assert.ok(
      notices.some((message) =>
        /BACKEND:cancel:aborted:.*STREAMED/s.test(message),
      ),
    );
    await request("prompt", { message: "/native-probe timeout" });
    assert.ok(
      notices.some((message) => /BACKEND:timeout:timeout:/.test(message)),
    );
    assert.deepEqual(errors, []);
    assert.ok(!/Failed to load extension/i.test(stderr), stderr);
  },
);
