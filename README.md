# MacIPadDisplay

Personal SideMini-like tool for a **monitor-free Mac mini → iPad** setup.

After one-time setup (with a monitor), the Mac auto-logins, this agent starts, waits for your iPad, connects **Sidecar** (Wi‑Fi/Bluetooth, USB preferred when present), reconnects on drop, stands aside when a real monitor is plugged in, optionally locks after first connect, and pushes **login / Sidecar connect/disconnect** alerts to your iPhone via **ntfy** or **Bark**.

> Requires **macOS 14+** and a Sidecar-capable iPad. Uses Apple’s private `SidecarCore` API (same approach as [sidecar-connect](https://github.com/say-michael/sidecar-connect) / [SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher)). May break on macOS updates.

## Features

- Auto Sidecar connect at login when no physical monitor is attached
- Wait-forever if the iPad is asleep; connect when you wake it
- Wired-first, wireless fallback
- ~0.5s poll while waiting, ~2s while stable; reconnect on drop
- Stand aside when a monitor is attached; resume when unplugged
- Optional lock-after-first-Sidecar-connect (safer with auto-login)
- iPhone safety pushes: session start, Sidecar up/down, login success/fail (via [loginwatcher](https://github.com/RamanaRaj7/loginwatcher))
- Menu-bar status + CLI
- Local logs under `~/Library/Logs/MacIPadDisplay/`

## Quick start (on your Mac mini)

```bash
git clone https://github.com/nitishberi/mac-ipad-display.git
cd mac-ipad-display
chmod +x Scripts/*.sh Scripts/hooks/*.sh
./Scripts/install.sh
```

Or install from a **DMG** (Releases): open the `.dmg`, drag `MacIPadDisplay.app` to Applications, launch once, then configure via the menu bar.

### Build a DMG yourself (macOS)

```bash
./Scripts/make-dmg.sh
# → dist/MacIPadDisplay-1.0.0.dmg
```

GitHub Actions also builds a DMG on `macos-14` for version tags (`v1.0.0`) or via workflow dispatch.

Then:

1. Edit `~/Library/Application Support/MacIPadDisplay/config.json`
   - Set `iPadName` to a substring of your iPad’s name
   - Set `ntfyURL` (install [ntfy](https://ntfy.sh) on iPhone and subscribe) **or** `barkURL`
2. `mac-ipad-display notify-test`
3. With a monitor attached: `mac-ipad-display list` then `mac-ipad-display connect --wait 30`
4. Follow **[docs/SETUP.md](docs/SETUP.md)** for FileVault off + automatic login (required for unattended boot)
5. Unplug the monitor, restart, wake the iPad — it should connect; your iPhone should get pushes

## CLI

```text
mac-ipad-display                  # menu bar + supervisor
mac-ipad-display list
mac-ipad-display connect --wait 30
mac-ipad-display watch            # headless supervisor only
mac-ipad-display install-agent --menubar
mac-ipad-display notify-test
```

## Uninstall

```bash
./Scripts/uninstall.sh          # keep config/logs
./Scripts/uninstall.sh --purge  # remove config/logs too
```

## Important limits

- Sidecar **cannot** show the FileVault/login screen on the iPad. Unattended boot needs **FileVault off + automatic login** (see SETUP.md).
- The iPad must be awake/unlocked to connect.
- Private API: rebuild after major macOS updates if connect breaks.

## License

MIT. SidecarCore bridging patterns adapted from open-source Sidecar CLIs (MIT). Not affiliated with Apple or SideMini.
