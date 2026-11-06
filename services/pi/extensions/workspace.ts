import {
  createBashToolDefinition,
  createLocalBashOperations,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { trustedWorkspace, withDirenv } from "./operations.ts";

export default function (pi: ExtensionAPI) {
  pi.registerTool(
    createBashToolDefinition(process.cwd(), {
      operations: withDirenv(
        createLocalBashOperations({ shellPath: "/bin/bash" }),
      ),
    }),
  );
  pi.on("user_bash", () => ({
    operations: withDirenv(
      createLocalBashOperations({ shellPath: "/bin/bash" }),
    ),
  }));
  pi.on("project_trust", (event) => ({
    trusted: trustedWorkspace(event.cwd) ? "yes" : "undecided",
    // Recheck the canonical path every time, instead of persisting a broad trust
    // decision that would survive a later symlink change.
  }));
}
