"""Portable-bundle installation tests; no network, sudo or host writes."""
import contextlib
import io
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tests.test_sudoers import cli


class PortableBundleInstall(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.prefix = self.root / "usr/local"
        self.cli_path = self.prefix / "bin/openp2s"
        self.vpn_path = self.prefix / "lib/openp2s/openvpn"
        for name, value in (("OPENP2S_BIN", str(self.cli_path)), ("OPENVPN_BIN", str(self.vpn_path))):
            mock = patch.object(cli, name, value)
            mock.start()
            self.addCleanup(mock.stop)
        self.real_run = subprocess.run
        self.privileged_calls = []

    def bundle(self, missing=None, linked=None):
        path = self.root / "bundle.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            files = {
                "openp2s": b"#!/bin/sh\nprintf '0.2.0\n'\n",
                "openvpn-openp2s": b"#!/bin/sh\nprintf 'OpenVPN\n'\n",
                "BUILDINFO": b"openp2s_version=0.2.0\n",
                "README.md": b"Not an installation tree.\n",
            }
            for name, data in files.items():
                if name == missing:
                    continue
                member = tarfile.TarInfo(f"openp2s-{cli.OPENP2S_VERSION}-linux-amd64/{name}")
                if name == linked:
                    member.type = tarfile.SYMTYPE
                    member.linkname = "/etc/passwd"
                    archive.addfile(member)
                else:
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
        return path

    def run_without_root(self, args, **kwargs):
        if args[0] == "sudo":
            self.privileged_calls.append(args)
            self.assertEqual(args[1], "install")
            self.assertIn("-o", args)
            self.assertIn("-g", args)
            self.assertEqual(args[args.index("-o") + 1], "root")
            self.assertEqual(args[args.index("-g") + 1], "root")
            # Perform actual file installation into the temporary prefix, but
            # leave ownership with the test user instead of invoking sudo.
            unprivileged = ["install"]
            i = 2
            while i < len(args):
                if args[i] in ("-o", "-g"):
                    i += 2
                else:
                    unprivileged.append(args[i])
                    i += 1
            args = unprivileged
        return self.real_run(args, **kwargs)

    def test_portable_layout_installs_runnable_binaries_and_metadata(self):
        archive = self.bundle()
        with patch.object(cli.subprocess, "run", side_effect=self.run_without_root):
            cli.install_openp2s_bundle(archive)
            cli.verify_openp2s_installation()
        installed = {p.relative_to(self.prefix).as_posix() for p in self.prefix.rglob("*") if p.is_file()}
        self.assertEqual(installed, {"bin/openp2s", "lib/openp2s/openvpn", "lib/openp2s/BUILDINFO"})
        self.assertEqual(self.cli_path.stat().st_mode & 0o777, 0o755)
        self.assertEqual(self.vpn_path.stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.vpn_path.parent / "BUILDINFO").stat().st_mode & 0o777, 0o644)
        self.assertEqual((self.vpn_path.parent / "BUILDINFO").read_text(), "openp2s_version=0.2.0\n")

    def test_missing_bundle_member_fails_before_privileged_install(self):
        with patch.object(cli.subprocess, "run") as run:
            with self.assertRaises(KeyError):
                cli.install_openp2s_bundle(self.bundle(missing="BUILDINFO"))
            run.assert_not_called()

    def test_link_in_place_of_binary_is_rejected_before_install(self):
        with patch.object(cli.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                cli.install_openp2s_bundle(self.bundle(linked="openvpn-openp2s"))
            run.assert_not_called()

    def test_privileged_install_failure_propagates(self):
        with patch.object(cli.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "install")):
            with self.assertRaises(subprocess.CalledProcessError):
                cli.install_openp2s_bundle(self.bundle())

    def test_verification_rejects_missing_binary(self):
        with self.assertRaises(FileNotFoundError):
            cli.verify_openp2s_installation()

    def test_setup_does_not_report_success_or_install_helper_for_broken_binary(self):
        self.cli_path.parent.mkdir(parents=True)
        self.vpn_path.parent.mkdir(parents=True)
        self.cli_path.write_text("#!/bin/sh\nexit 0\n")
        self.vpn_path.write_text("#!/bin/sh\nexit 1\n")
        os.chmod(self.cli_path, 0o755)
        os.chmod(self.vpn_path, 0o755)
        output = io.StringIO()
        with patch.object(cli.platform, "machine", return_value="x86_64"), \
                patch.object(cli.subprocess, "run", side_effect=self.run_without_root), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(cli.cmd_setup(), 1)
        self.assertIn("installation is not usable", output.getvalue())
        self.assertNotIn("Setup complete", output.getvalue())
        self.assertEqual(self.privileged_calls, [])


if __name__ == "__main__":
    unittest.main()
