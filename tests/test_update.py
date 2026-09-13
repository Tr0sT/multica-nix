"""Offline regression tests for the updater; Nix builds are stubbed here.

The real package builds and NixOS VM remain covered by nix flake check.
"""

import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HASHES = ["sha256-" + base64.b64encode(bytes([n]) * 32).decode() for n in range(1, 6)]

MOCK_NIX = r'''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
log = Path("nix-calls.jsonl")
calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
with log.open("a") as out:
    out.write(json.dumps(args) + "\n")
hashes = json.loads(os.environ["TEST_HASHES"])
mode = os.environ.get("TEST_FAILURE", "")
if args[0] == "build":
    if args.count(".#multica-server") and ".#multica-cli" in args:
        sys.exit(8 if mode == "verify" else 0)
    stage = sum(call[0] == "build" for call in calls)
    if mode == "vendor" and stage == 1:
        print("go: updates to go.mod needed", file=sys.stderr)
        sys.exit(7)
    if mode == "unexpected-success":
        sys.exit(0)
    expected = ".#multica-web" if stage == 2 else ".#multica-server"
    assert args[1] == expected, args
    print("error: hash mismatch\n  specified: sha256-AAAA\n  got: " + hashes[stage], file=sys.stderr)
    sys.exit(1)
if args[:2] == ["store", "prefetch-file"]:
    if mode == "prefetch":
        print("download failed", file=sys.stderr)
        sys.exit(9)
    print(json.dumps({"hash": hashes[4 if "arm64" in args[-1] else 3]}))
    sys.exit(0)
assert args == ["fmt"], args
'''


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        (self.work / "packages").mkdir()
        (self.work / "bin").mkdir()
        (self.work / "flake.nix").write_text('version = "0.4.42";\n')
        header = '{ version ? "0.4.42", ... }: {\n'
        source = 'src = fetchFromGitHub {\n  hash = "OLD";\n};\n'
        files = {
            "server": source + 'vendorHash = "OLD";\n',
            "web": source + 'pnpmDeps = fetchPnpmDeps {\n  hash = "OLD";\n};\n',
            "cli": 'x86_64-linux = {\n  hash = "OLD";\n};\naarch64-linux = {\n  hash = "OLD";\n};\n',
        }
        for name, body in files.items():
            (self.work / "packages" / f"multica-{name}.nix").write_text(header + body + '}\n')
        executable = self.work / "bin/nix"
        executable.write_text(f"#!{sys.executable}\n" + MOCK_NIX)
        executable.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": str(self.work / "bin") + os.pathsep + os.environ["PATH"],
            "TEST_HASHES": json.dumps(HASHES),
            "TEST_FAILURE": "",
            "VERIFY_BUILDS": "0",
            "RUN_VM_TEST": "0",
            "LOG_FILE": str(self.work / "update.log"),
        }
        git = self.work / "bin/git"
        git.write_text(f"#!{sys.executable}\nimport sys\nassert sys.argv[1:] == ['diff', '--stat']\n")
        git.chmod(0o755)

    def run_update(self, version="0.4.43", **env):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/update.sh"), "--version", version],
            cwd=self.work, env={**self.env, **env}, text=True, capture_output=True, timeout=30,
        )

    def contents(self):
        return {str(p.relative_to(self.work)): p.read_text() for p in self.work.rglob("*.nix")}

    def assert_complete(self):
        text = "\n".join(self.contents().values())
        self.assertNotIn("lib.fakeHash", text)
        self.assertNotIn("OLD", text)
        self.assertNotIn('"0.4.42"', text)
        for value in HASHES:
            self.assertIn(value, text)
        self.assertEqual(text.count(HASHES[0]), 2)  # shared source hash

    def test_new_version_updates_every_hash(self):
        result = self.run_update("v0.4.43")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_complete()

    def test_complete_same_version_is_a_noop(self):
        before = self.contents()
        result = self.run_update("0.4.42")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.contents(), before)
        self.assertFalse((self.work / "nix-calls.jsonl").exists())

    def test_same_version_retries_each_placeholder_location(self):
        for name, field in [("server", "hash"), ("server", "vendorHash"), ("web", "hash"), ("cli", "hash")]:
            with self.subTest(package=name, field=field):
                path = self.work / "packages" / f"multica-{name}.nix"
                text = re.sub(rf'({field} = )"[^"]+";', r'\1lib.fakeHash;', path.read_text())
                path.write_text(text)
                (self.work / "nix-calls.jsonl").unlink(missing_ok=True)
                result = self.run_update("0.4.42")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Retrying incomplete update", result.stdout)
                self.assertNotIn("lib.fakeHash", "\n".join(self.contents().values()))

    def test_failed_vendor_does_not_reuse_source_hash_and_can_be_retried(self):
        result = self.run_update(TEST_FAILURE="vendor")
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertIn('vendorHash = lib.fakeHash;', (self.work / "packages/multica-server.nix").read_text())
        log = (self.work / "update.log").read_text()
        self.assertIn(HASHES[0], log)
        self.assertIn("go: updates to go.mod needed", log)
        (self.work / "nix-calls.jsonl").unlink()
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_complete()

    def test_unexpected_success_is_not_a_discovered_hash(self):
        result = self.run_update(TEST_FAILURE="unexpected-success")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected a hash mismatch", result.stderr)

    def test_prefetch_failure_is_not_success(self):
        result = self.run_update(TEST_FAILURE="prefetch")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Update complete", result.stdout)

    def test_final_verification_failure_is_not_success(self):
        result = self.run_update(VERIFY_BUILDS="1", TEST_FAILURE="verify")
        self.assertEqual(result.returncode, 8, result.stdout + result.stderr)
        self.assertNotIn("Update complete", result.stdout)

    def test_go_patch_keeps_a_released_minimum(self):
        package = (ROOT / "packages/multica-server.nix").read_text()
        match = re.search(r"sed -i -E '([^']+)' server/go.mod", package)
        self.assertIsNotNone(match)
        result = subprocess.run(
            ["sed", "-E", match.group(1)], input="module example.com/test\n\ngo 1.26.6\n",
            text=True, capture_output=True, check=True,
        )
        self.assertIn("\ngo 1.26.0\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
