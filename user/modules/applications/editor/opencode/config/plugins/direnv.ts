// https://github.com/simonwjackson/opencode-direnv/issues/1#issuecomment-3940887423

import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "direnv",
  async setup(ctx) {
    let logged = false

    const log = (message: string) => {
      console.log(`[direnv] ${message}`)
    }

    await ctx.shell.hook("create.before", async (event) => {
      const firstRun = !logged
      logged = true

      try {
        const proc = Bun.spawn(["direnv", "export", "json"], {
          cwd: event.cwd,
          stdout: "pipe",
          stderr: "pipe",
        })
        const text = await new Response(proc.stdout).text()
        await proc.exited

        if (text.trim() === "") {
          if (firstRun) log(".envrc already loaded")
          return
        }

        Object.assign(event.env, JSON.parse(text))
        if (firstRun) log(".envrc loaded")
      } catch (err) {
        log(`.envrc failed to load: ${err}`)
      }
    })
  },
})
