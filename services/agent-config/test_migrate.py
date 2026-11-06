import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


def load(name, source):
    spec = importlib.util.spec_from_file_location(name, source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


migration = load("migration", Path(__file__).with_name("migrate.py"))
setup = load("setup", Path(__file__).parent.parent / "pi/setup.py")
direnv = load("direnv", Path(__file__).parent.parent / "pi/direnv.py")


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.destination = self.root / "agent-config"
        self.state = self.root / "state"
        self.store = self.root / "private-store"
        self.write(".config/opencode/AGENTS.md", "Exact instructions\n")
        self.write(".config/opencode/skills/one/SKILL.md", "one\n")
        self.write(".agents/skills/two/SKILL.md", "two\n")

    def write(self, relative, text):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def run_migration(self):
        migration.migrate(self.home, self.destination, self.state, self.store)

    def test_exact_copy_backup_and_restart_preserves_edits(self):
        config = self.write(".config/opencode/opencode.json", '{"unrelated":true}')
        self.run_migration()
        self.assertEqual(
            (self.destination / "AGENTS.md").read_text(), "Exact instructions\n"
        )
        self.assertEqual(
            (self.destination / "skills/two/SKILL.md").read_text(), "two\n"
        )
        self.assertEqual(
            (self.state / "original/AGENTS.md").read_text(), "Exact instructions\n"
        )
        self.assertEqual(
            (self.home / ".config/opencode/AGENTS.md").readlink(),
            Path("/agent-config/AGENTS.md"),
        )
        self.assertFalse((self.home / ".agents/skills").exists())
        (self.destination / "AGENTS.md").write_text("Later user edit")
        self.run_migration()
        self.assertEqual(
            (self.destination / "AGENTS.md").read_text(), "Later user edit"
        )
        self.assertEqual(config.read_text(), '{"unrelated":true}')
        self.assertIn(
            "skills/one/SKILL.md", json.loads((self.state / "seed.json").read_text())
        )

    def test_duplicate_conflict_changes_neither_source_nor_host(self):
        self.write(".agents/skills/one/SKILL.md", "duplicate")
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.run_migration()
        self.assertFalse((self.home / ".config/opencode/AGENTS.md").is_symlink())
        self.assertFalse((self.state / "seed.json").exists())
        self.assertFalse((self.destination / "AGENTS.md").exists())

    def test_existing_host_conflict_is_not_overwritten(self):
        self.destination.mkdir()
        (self.destination / "AGENTS.md").write_text("Existing host instructions")
        with self.assertRaisesRegex(ValueError, "conflicts"):
            self.run_migration()
        self.assertEqual(
            (self.destination / "AGENTS.md").read_text(), "Existing host instructions"
        )
        self.assertFalse((self.destination / "skills").exists())

    def test_interrupted_copy_can_resume_without_marker(self):
        (self.destination / "skills/one").mkdir(parents=True)
        (self.destination / "skills/one/SKILL.md").write_text("one\n")
        self.run_migration()
        self.assertTrue((self.state / "seed.json").exists())

    def test_materialize_container_absolute_store_links(self):
        path = self.store / "fake-skill"
        path.mkdir(parents=True)
        (path / "SKILL.md").write_text("Portable\n")
        (self.home / ".agents/skills/store-skill").symlink_to("/nix/store/fake-skill")
        self.run_migration()
        copy = self.destination / "skills/store-skill"
        self.assertFalse(copy.is_symlink())
        self.assertEqual((copy / "SKILL.md").read_text(), "Portable\n")

    def test_host_symlink_escape_rejected(self):
        self.destination.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        (self.destination / "skills").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "Unsafe destination"):
            self.run_migration()
        self.assertEqual(list(outside.iterdir()), [])


class SetupTest(unittest.TestCase):
    def test_reconcile_owned_paths_and_preserve_preferences_and_auth(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            setup.setup(home, Path("/nix/store/old-extensions"))
            agent = home / ".pi/agent"
            settings = json.loads((agent / "settings.json").read_text())
            settings.update(defaultModel="my-model")
            settings["extensions"].append("/my/custom.ts")
            (agent / "settings.json").write_text(json.dumps(settings))
            (agent / "auth.json").write_text("private")
            t3 = home / ".t3/userdata/settings.json"
            defaults = json.loads(t3.read_text())
            self.assertTrue(defaults["providerInstances"]["pi"]["enabled"])
            self.assertFalse(defaults["providerInstances"]["claudeAgent"]["enabled"])
            t3.write_text('{"later-user-choice":true}')
            setup.setup(home, Path("/nix/store/new-extensions"))
            settings = json.loads((agent / "settings.json").read_text())
            self.assertEqual(settings["defaultModel"], "my-model")
            self.assertEqual(settings["extensions"][0], "/my/custom.ts")
            self.assertEqual(len(settings["extensions"]), 4)
            self.assertTrue(
                all("old-extensions" not in p for p in settings["extensions"])
            )
            self.assertEqual((agent / "auth.json").read_text(), "private")
            self.assertEqual(t3.read_text(), '{"later-user-choice":true}')


class DirenvScopeTest(unittest.TestCase):
    def test_whitelist_only_for_actual_scoped_envrc(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            direnv.NIX_ROOT = workspace / "nix"
            direnv.CODE_ROOT = workspace / "code"
            for relative in ["nix", "code/project/nested", "outside", "nix-other"]:
                (workspace / relative).mkdir(parents=True)
            envrc = workspace / "code/project/.envrc"
            envrc.write_text("export EXAMPLE=one")
            self.assertEqual(
                direnv.config_scope(workspace / "code/project/nested"), "trusted"
            )
            envrc.write_text("export EXAMPLE=changed")
            self.assertEqual(direnv.config_scope(workspace / "code/project"), "trusted")
            (workspace / "code/.envrc").write_text("outside scope")
            self.assertEqual(direnv.config_scope(workspace / "code"), "manual")
            for relative in ["outside", "nix-other"]:
                (workspace / relative / ".envrc").write_text("manual")
                self.assertEqual(direnv.config_scope(workspace / relative), "manual")
            envrc.unlink()
            envrc.symlink_to(workspace / "outside/.envrc")
            self.assertEqual(direnv.config_scope(workspace / "code/project"), "manual")
            (workspace / "code/escape").symlink_to(
                workspace / "outside", target_is_directory=True
            )
            self.assertEqual(direnv.config_scope(workspace / "code/escape"), "manual")


if __name__ == "__main__":
    unittest.main()
