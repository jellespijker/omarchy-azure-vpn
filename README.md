# Omarchy Azure VPN Plugin

A fast, lightweight, and completely headless **Microsoft Azure Point-to-Site (P2S) VPN** widget for the [Omarchy](https://omarchy.org/) desktop shell.

![Azure VPN Plugin Preview](preview.png)

## Features

- **Headless & Fast**: Replaces the deprecated, bulky Flutter GUI client (`microsoft-azurevpnclient`) with a native OpenVPN/OpenP2S backend.
- **Microsoft Entra ID (Azure AD) SSO**: Authenticates with browser-based PKCE SSO and automatically caches and refreshes OAuth tokens.
- **Top Bar Integration**:
  - **Left-click**: Opens the connection panel with profile management, connection state, and live telemetry.
  - **Right-click**: Instantly connects or disconnects the active profile.
  - **Status Indicator**: Glowing icon when connected, dimmed when disconnected, warning color on connection failure.
- **Profile Management**: Import any standard Azure VPN `.xml` package directly from a file dialog or CLI with automatic XML validation.
- **Split DNS & Routing**: Automatically resolves enterprise DNS via `systemd-resolved` (`resolvectl`) and routes corporate subnets.
- **Systemd Managed**: Background tunnel managed as an isolated `systemd --user` service.
- **Least-privilege root access**: sudo is granted only to a root-owned helper with five exact command lines; see [Security model](#security-model).

---

## Installation & Setup

### 1. Add Plugin to Omarchy

```bash
omarchy plugin add https://github.com/jellespijker/omarchy-azure-vpn.git --enable
```

*(Optional)* To use the `azurevpn` command-line utility from anywhere in your shell:
```bash
ln -sf ~/.config/omarchy/plugins/jellespijker.azure-vpn/bin/azurevpn ~/.local/bin/azurevpn
```

### 2. Run Dependency Setup

Azure VPN uses Microsoft Entra ID tokens which exceed standard OpenVPN credential buffer sizes. The plugin uses [`openp2s`](https://github.com/wyruweso/openp2s) with a patched OpenVPN binary.

Run the built-in setup wizard:

```bash
~/.config/omarchy/plugins/jellespijker.azure-vpn/bin/azurevpn setup
```

This will:
1. Verify or automatically install `openp2s` and its companion OpenVPN binary into `/usr/local/bin` and `/usr/local/lib/openp2s/` (verified against SHA256 checksum).
2. Install a small root-owned helper to `/usr/local/lib/azurevpn/azurevpn-helper` (`root:root`, `0755`, in a root-owned `0755` directory) and a sudoers rule in `/etc/sudoers.d/99-azurevpn` (validated with `visudo -c` before install) that lets your user run **only that helper**, with one explicit command line per operation (see [Security model](#security-model)). A legacy `/etc/sudoers.d/99-openp2s` rule from plugin versions before 1.0.2 is removed.
3. Secure profile and token directory permissions (`0700` / `0600`).
4. Register the systemd user service (`azure-vpn.service`).

---

## Security model

Earlier versions (<= 1.0.1) granted passwordless root for `/usr/local/lib/openp2s/openvpn` and `resolvectl` with unrestricted arguments. OpenVPN accepts script and plugin options (`--script-security`, `--up`, `--plugin`, `--config`, ...), so that was equivalent to passwordless root. Since 1.0.2 sudo is granted to a helper only.

**What sudo allows.** The sudoers rule (`/etc/sudoers.d/99-azurevpn`) names exactly five command lines and no wildcards:

```
/usr/local/lib/azurevpn/azurevpn-helper connect
/usr/local/lib/azurevpn/azurevpn-helper dns-servers
/usr/local/lib/azurevpn/azurevpn-helper dns-domains
/usr/local/lib/azurevpn/azurevpn-helper dns-default-route
/usr/local/lib/azurevpn/azurevpn-helper dns-revert
```

No subcommand takes arguments, so a caller cannot append options. The environment is reset (`env_reset`, `!setenv`).

**What the helper does.**

- `connect` reads the config that `openp2s` wrote to `/run/user/<your uid>/openp2s/openvpn.conf` (path derived from `SUDO_UID`, never supplied; must be a regular, non-symlink file owned by you). It validates every directive against an allow-list, rebuilds a clean copy in the root-only `/run/azurevpn/`, and runs the root-owned `/usr/local/lib/openp2s/openvpn --config <that copy>` with a minimal environment. No other option is ever passed.
- It **rejects** anything outside the allow-list, including `script-security`, `up`, `down`, `plugin`, `route-up`, `route-pre-down`, `ipchange`, `learn-address`, `tls-verify`, `client-connect`, `client-disconnect`, `auth-user-pass-verify`, `config`, `include`, `setenv`, `cd`, `chroot`, `management-client-user`, file-path options such as `key`, `cert`, `log`, `status`, `writepid`, credentials *files*, `ca` paths other than known system CA bundles, and control characters, quotes, `;`, `#` or backslashes in a directive. Inline blocks other than `<ca>` and `<tls-auth>` are rejected, and block bodies must be PEM or key material.
- The management socket must sit directly in your own `/run/user/<uid>/openp2s/` directory. The Entra token only travels over it, never through files or arguments.
- `dns-*` read the interface and values from stdin and run fixed `resolvectl dns|domain|default-route <if> no|revert` operations. The interface must match `tun<N>` and be a real tun device; DNS servers must be IP addresses; domains must be valid DNS names (or `~.`).

`openp2s` itself runs unprivileged and calls `sudo`; the plugin puts a small shim named `sudo` (`libexec/azurevpn-sudo`) first on `PATH` **for that process only**. It translates the two command shapes `openp2s` uses into helper calls and refuses everything else. The shim is a convenience, not a security boundary: the helper and the sudoers rule are.

**Residual trust.** You can still ask the helper to start a tunnel to a gateway named in a config you control, as with any "user may start a VPN" policy. The helper does not hard-code Azure gateway names.

### What is installed where

| Path | Owner / mode | Purpose |
|---|---|---|
| `/usr/local/lib/azurevpn/azurevpn-helper` | `root:root` `0755` | privileged helper |
| `/etc/sudoers.d/99-azurevpn` | `root:root` `0440` | exact-command rule for the helper |
| `/run/azurevpn/` | `root` `0700` (tmpfs) | validated config copy, created at connect time |
| `/usr/local/bin/openp2s`, `/usr/local/lib/openp2s/` | root | upstream binaries (existing install, or by `azurevpn setup`) |
| `~/.config/azure-vpn/` | you `0700` | profiles and settings |
| `~/.config/systemd/user/azure-vpn.service` | you | background service |

### Running the tests

```bash
python3 -m unittest discover -s tests -t .
```

The tests need no root and no VPN; they cover helper argument and config validation (including negative cases for `script-security`, `up`/`down`, `plugin`, `--config` and path traversal) and the generated sudoers text.

---

## Usage

### Importing a Profile

1. Click the Azure VPN icon on your Omarchy bar.
2. Click **Import** in the popout panel to select your Azure VPN `.xml` file (requires `zenity` for GUI picker).
3. Or import directly from the command line:
   ```bash
   azurevpn import ~/Downloads/azurevpnconfig.xml
   ```

### Connecting & Disconnecting

- **From the bar**: Click the bar widget and press **Connect**, or simply **right-click** the bar icon to toggle immediately.
- **From CLI**:
  ```bash
  azurevpn connect           # Connects active profile (opens browser if auth needed)
  azurevpn disconnect        # Disconnects
  azurevpn toggle            # Toggles connection
  azurevpn status            # Shows IP, interface, DNS, uptime
  azurevpn list              # Lists available profiles
  azurevpn select <profile>  # Switches active profile
  ```

---

## Troubleshooting

- **Check connection service logs**:
  ```bash
  journalctl --user -u azure-vpn -f
  ```
- **Inspect OpenP2S diagnostic checks**:
  ```bash
  openp2s doctor ~/.config/azure-vpn/profiles/<profile>.xml
  ```
- **Check Entra ID authentication cache**:
  ```bash
  openp2s auth status ~/.config/azure-vpn/profiles/<profile>.xml
  ```

---

## Changelog

### 1.0.2

- **Security:** replaced the unrestricted passwordless-root sudoers grant for `openvpn` and `resolvectl` with a root-owned helper (`/usr/local/lib/azurevpn/azurevpn-helper`) and an exact-command sudoers rule. The helper rejects OpenVPN script/plugin/config options and arbitrary file paths and validates every argument. `azurevpn setup` removes the old `/etc/sudoers.d/99-openp2s` rule. **Existing installs: re-run `azurevpn setup` after updating**, otherwise connecting fails (the old rule is no longer used).
- Added unit tests for the helper and the sudoers rule.

### 1.0.1

- Added CI validation and release workflows.

---

## Release & Versioning

Omarchy plugins track the default branch (`main`) directly when installed via `omarchy plugin add` or updated via `omarchy plugin update`. Official versions are tagged and published through GitHub Releases:

1. Update the version in `manifest.json` following Semantic Versioning (`X.Y.Z`).
2. Run validation locally:
   ```bash
   bash .github/scripts/validate-plugin.sh   # also runs the unit tests
   # or
   omarchy plugin validate .
   ```
3. Commit and push the changes to `main`.
4. Tag and push the new version:
   ```bash
   git tag v1.0.2
   git push origin v1.0.2
   ```
5. The GitHub Actions release workflow automatically verifies manifest parity, packages distribution archives with SHA256 checksums, and publishes the GitHub Release notes.

---

## Uninstallation / Teardown

To cleanly remove the systemd user service, the sudoers rule (`/etc/sudoers.d/99-azurevpn`, and the legacy `99-openp2s` if present), the helper (`/usr/local/lib/azurevpn/`) and `/run/azurevpn`:
```bash
azurevpn teardown
omarchy plugin remove jellespijker.azure-vpn
```
`teardown` asks for your sudo password once. It does not remove `openp2s` itself.

---

## Legal, Trademarks & Architecture Notice

- **Independent Community Project**: This project is an independent open-source contribution and is not affiliated with, endorsed by, sponsored by, or associated with Microsoft Corporation in any way.
- **Trademarks**: "Microsoft", "Azure", "Microsoft Entra ID", and related marks are trademarks of Microsoft Corporation. They are used here solely for descriptive and compatibility identification purposes.
- **No Proprietary Software**: This repository does not contain, vendor, or distribute any proprietary binaries, source code, or assets from Microsoft's official `microsoft-azurevpnclient` application (which is governed by Microsoft's proprietary EULA).
- **Backend Components & Licensing**:
  - This Omarchy plugin (`jellespijker.azure-vpn`) and its Python CLI orchestrator are original works licensed under the [MIT License](LICENSE).
  - The underlying VPN connection engine relies on [`openp2s`](https://github.com/wyruweso/openp2s) and [OpenVPN](https://openvpn.net/), both open-source projects licensed under the **GNU General Public License v2 (GPL-2.0)**.
  - The plugin communicates with `openp2s` exclusively across standard process boundaries via command-line invocations and standard I/O pipes. No third-party binaries are vendored into this repository.

---

## License

MIT © Jelle Spijker
