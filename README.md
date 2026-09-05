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
2. Configure a scoped sudoers rule in `/etc/sudoers.d/99-openp2s` (validated via `visudo -c`) granting your specific user account passwordless execution for `/usr/local/lib/openp2s/openvpn` and `/usr/bin/resolvectl`.
3. Secure profile and token directory permissions (`0700` / `0600`).
4. Register the systemd user service (`azure-vpn.service`).

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

## Uninstallation / Teardown

To cleanly remove the systemd user service and the sudoers file:
```bash
azurevpn teardown
omarchy plugin remove jellespijker.azure-vpn
```

---

## License

MIT © Jelle Spijker
