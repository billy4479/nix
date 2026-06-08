// https://github.com/simonwjackson/opencode-direnv/issues/1#issuecomment-3940887423

import type { Plugin } from "@opencode-ai/plugin"

export const DirenvPlugin: Plugin = async ({ client, $ }) => {
  const notify = async (message: string, variant: "info" | "success" | "error") => {
    try {
      await client.tui.showToast({ body: { message, variant } })
    } catch {
      // Toasts are best-effort; direnv loading should not depend on the UI.
    }
  }

  return {
    async "shell.env"(input, output) {
      try {
        await notify("direnv: loading .envrc", "info")
        const localEnv = await $`direnv export json`.cwd(input.cwd).json();
        Object.assign(output.env, localEnv)
        await notify("direnv: .envrc loaded", "success")
        client.app.log({
          body: {
            service: "direnv",
            level: "info",
            message: ".envrc loaded",
            extra: { DIRENV_FILE: localEnv.DIRENV_FILE, cwd: input.cwd },
          },
        })
      } catch (err) {
        await notify("direnv: .envrc failed to load", "error")
        client.app.log({
          body: {
            service: "direnv",
            level: "error",
            message: ".envrc failed to load",
            extra: { cwd: input.cwd, err },
          },
        })
      }
    },
  }
}
