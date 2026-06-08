// https://github.com/simonwjackson/opencode-direnv/issues/1#issuecomment-3940887423

import type { Plugin } from "@opencode-ai/plugin"

export const DirenvPlugin: Plugin = async ({ client, $ }) => {
  let notified = false

  const notify = async (message: string, variant: "info" | "success" | "error") => {
    try {
      await client.tui.showToast({ body: { message, variant } })
    } catch {
      // Toasts are best-effort; direnv loading should not depend on the UI.
    }
  }

  const log = async (level: "info" | "error", message: string, extra: Record<string, unknown>) => {
    try {
      await client.app.log({
        body: {
          service: "direnv",
          level,
          message,
          extra,
        },
      })
    } catch {
      // Logging is best-effort too.
    }
  }

  return {
    async "shell.env"(input, output) {
      const shouldNotify = !notified
      notified = true

      try {
        if (shouldNotify) await notify("direnv: loading .envrc", "info")

        const text = await $`direnv export json`.cwd(input.cwd).text()
        if (text.trim() === "") {
          if (shouldNotify) await notify("direnv: .envrc loaded", "success")
          await log("info", ".envrc already loaded", { cwd: input.cwd })
          return
        }

        const localEnv = JSON.parse(text)
        Object.assign(output.env, localEnv)
        if (shouldNotify) await notify("direnv: .envrc loaded", "success")
        await log("info", ".envrc loaded", { DIRENV_FILE: localEnv.DIRENV_FILE, cwd: input.cwd })
      } catch (err) {
        if (shouldNotify) await notify("direnv: .envrc failed to load", "error")
        await log("error", ".envrc failed to load", { cwd: input.cwd, err })
      }
    },
  }
}
