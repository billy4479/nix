import { Plugin } from "@opencode/plugin"

const ERROR_MESSAGE =
  "Refusing to search the whole Nix store. /nix/store is huge and content-addressed; broad glob/grep/list operations are slow and usually not useful. Use the nix CLI to locate the store path first, then access that precise path instead."

const GUARDED_TOOLS = new Set(["glob", "grep", "read"])

function isBroadNixStorePath(value: string) {
  const normalized = value.replace(/\/+/g, "/")

  if (normalized === "/nix/store" || normalized === "/nix/store/") return true
  if (!normalized.startsWith("/nix/store/")) return false

  const rest = normalized.slice("/nix/store/".length)
  const firstSegment = rest.split("/")[0]
  return firstSegment === "" || firstSegment.includes("*") || firstSegment.includes("?")
}

function strings(values: unknown[]) {
  return values.filter((value): value is string => typeof value === "string")
}

function getPathArgs(tool: string, args: Record<string, unknown>) {
  if (tool === "glob") return strings([args.path, args.pattern])
  if (tool === "grep") return strings([args.path])
  if (tool === "read") return strings([args.path, args.filePath])
  return []
}

export default Plugin.define({
  id: "nix-store-guard",
  async setup(ctx) {
    await ctx.tool.hook("execute.before", (event) => {
      if (!GUARDED_TOOLS.has(event.tool)) return

      const args = (event.input ?? {}) as Record<string, unknown>
      const paths = getPathArgs(event.tool, args)
      if (paths.some(isBroadNixStorePath)) throw new Error(ERROR_MESSAGE)
    })
  },
})
