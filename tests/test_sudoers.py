"""Tests for the sudoers rule that `azurevpn setup` generates."""
import importlib.machinery
import importlib.util
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_loader = importlib.machinery.SourceFileLoader("azurevpn_cli", str(ROOT / "bin" / "azurevpn"))
_spec = importlib.util.spec_from_loader("azurevpn_cli", _loader)
cli = importlib.util.module_from_spec(_spec)
_loader.exec_module(cli)


def logical_lines(text):
    return re.sub(r"\\\n\s*", "", text).splitlines()


class SudoersRule(unittest.TestCase):
    def setUp(self):
        self.text = cli.build_sudoers_rule("alice")
        self.lines = [ln for ln in logical_lines(self.text) if ln and not ln.startswith("#")]

    def test_only_the_helper_is_granted(self):
        alias = next(ln for ln in self.lines if ln.startswith("Cmnd_Alias"))
        cmds = [c.strip() for c in alias.split("=", 1)[1].split(",")]
        self.assertEqual(cmds, [f"{cli.HELPER_PATH} {s}" for s in cli.HELPER_SUBCOMMANDS])
        grant = next(ln for ln in self.lines if ln.startswith("alice "))
        self.assertEqual(grant, "alice ALL=(root) NOPASSWD: AZUREVPN_HELPER")

    def test_no_wildcards_no_raw_binaries_no_all(self):
        self.assertNotIn("*", self.text)
        self.assertNotIn("openp2s/openvpn", self.text)
        self.assertNotIn("resolvectl", self.text)
        self.assertNotRegex(self.text, r"NOPASSWD:\s*ALL")
        self.assertNotRegex(self.text, r"\(ALL")
        self.assertEqual(len([ln for ln in self.lines if "NOPASSWD" in ln]), 1)

    def test_every_command_has_an_exact_fixed_argument(self):
        for sub in cli.HELPER_SUBCOMMANDS:
            self.assertRegex(self.text, re.escape(f"{cli.HELPER_PATH} {sub}") + r"(,|\n)")
        self.assertEqual(len(cli.HELPER_SUBCOMMANDS), 5)

    def test_helper_lives_in_root_owned_system_dir(self):
        self.assertTrue(cli.HELPER_PATH.startswith("/usr/local/lib/"))
        self.assertNotIn("/home", self.text)

    def test_env_is_reset_and_setenv_denied(self):
        self.assertIn("Defaults!AZUREVPN_HELPER env_reset, !setenv", self.text)

    def test_hostile_user_names_rejected(self):
        for user in ("", "ALL", "root", "a b", "x\nALL ALL=(ALL) NOPASSWD: ALL", "%wheel", "a,b", "a=b",
                     "../x", "-x", "Alice", "a" * 40, "user#", "!user", "x:y"):
            with self.subTest(user=user):
                with self.assertRaises(ValueError):
                    cli.build_sudoers_rule(user)

    def test_hostile_helper_paths_rejected(self):
        for p in ("relative", "/x/../etc", "/a b", "/a,/bin/sh", "/a\nb", "/a*", ""):
            with self.subTest(p=p):
                with self.assertRaises(ValueError):
                    cli.build_sudoers_rule("alice", helper_path=p)

    @unittest.skipUnless(shutil.which("visudo"), "visudo not installed")
    def test_visudo_accepts_rule(self):
        with tempfile.TemporaryDirectory() as td:
            f = Path(td) / "99-azurevpn"
            f.write_text(self.text)
            res = subprocess.run(["visudo", "-c", "-f", str(f)], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)


class ServiceAndInstallConstants(unittest.TestCase):
    def test_legacy_rule_is_cleaned_up_by_name(self):
        src = (ROOT / "bin" / "azurevpn").read_text()
        self.assertIn('LEGACY_SUDOERS_FILE = "/etc/sudoers.d/99-openp2s"', src)
        self.assertIn("for rule_file in (SUDOERS_FILE, LEGACY_SUDOERS_FILE)", src)
        self.assertIn("rm\", \"-rf\", HELPER_DIR", src)

    def test_setup_no_longer_grants_raw_binaries(self):
        src = (ROOT / "bin" / "azurevpn").read_text()
        self.assertNotIn("NOPASSWD: /usr/local/lib/openp2s/openvpn", src)
        self.assertNotIn("resolvectl_bin", src)

    def test_unit_stops_through_shim_wrapper(self):
        src = (ROOT / "bin" / "azurevpn").read_text()
        self.assertIn("ExecStop={SELF_PATH} daemon-stop", src)


if __name__ == "__main__":
    unittest.main()
