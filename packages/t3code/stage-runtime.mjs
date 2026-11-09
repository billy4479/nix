// Run from the server workspace so yaml resolves through its node_modules.
import fs from "node:fs";
import path from "node:path";
import YAML from "yaml";
import { selectCliRuntimeExternalDependencies } from "../../scripts/lib/cli-external-packages.ts";

const destination = process.argv[2];
const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const readYaml = (file) => YAML.parse(fs.readFileSync(file, "utf8"));
const writeYaml = (file, value) =>
  fs.writeFileSync(path.join(destination, file), YAML.stringify(value));

const server = readJson("apps/server/package.json");
const dependencies = selectCliRuntimeExternalDependencies(server.dependencies);
const workspace = readYaml("pnpm-workspace.yaml");
// pnpm 12 keeps package-manager dependencies in a separate YAML document.
const lockDocuments = YAML.parseAllDocuments(fs.readFileSync("pnpm-lock.yaml", "utf8"));
const lock = lockDocuments.at(-1).toJS();
const importer = lock.importers["apps/server"];

// Keep the original specifiers and resolved versions together. A frozen,
// offline install can then select the transitive closure without re-resolving
// version ranges or shipping the workspace's build dependencies.
lock.importers = {
  ".": {
    dependencies: Object.fromEntries(
      Object.entries(importer.dependencies).filter(([name]) => name in dependencies),
    ),
  },
};
delete workspace.packages;

fs.mkdirSync(destination, { recursive: true });
fs.writeFileSync(
  path.join(destination, "package.json"),
  JSON.stringify({
    name: "t3-runtime",
    version: server.version,
    private: true,
    type: "module",
    packageManager: readJson("package.json").packageManager,
    dependencies,
  }),
);
writeYaml("pnpm-workspace.yaml", workspace);
lockDocuments[lockDocuments.length - 1] = new YAML.Document(lock);
fs.writeFileSync(
  path.join(destination, "pnpm-lock.yaml"),
  lockDocuments.map((document) => `---\n${document}`).join("\n"),
);
fs.cpSync("patches", path.join(destination, "patches"), { recursive: true });
fs.copyFileSync(".pnpmfile.cjs", path.join(destination, ".pnpmfile.cjs"));
