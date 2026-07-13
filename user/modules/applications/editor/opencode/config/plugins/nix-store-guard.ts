import type { Plugin } from "@opencode-ai/plugin"

const ERROR_MESSAGE =
  "Refusing to search the whole Nix store. /nix/store is huge and content-addressed; broad glob/grep/list operations are slow and usually not useful. Use the nix CLI to locate the store path first, then access that precise path instead."

const GUARDED_TOOLS = new Set(["glob", "grep", "list"])

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
  if (tool === "list") return strings([args.path])
  return []
}

export const NixStoreGuardPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (!GUARDED_TOOLS.has(input.tool)) return

      const paths = getPathArgs(input.tool, output.args as Record<string, unknown>)
      if (paths.some(isBroadNixStorePath)) throw new Error(ERROR_MESSAGE)
    },
  }
}
