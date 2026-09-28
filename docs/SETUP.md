# Setup guide — Mac mini → iPad (personal)

This matches SideMini’s honest boot story: Sidecar only works **after** a user session. For a screen ASAP with no monitor, use **automatic login**.

## 1. Prerequisites

- Apple silicon Mac mini (or Studio) on **macOS 14+**
- Sidecar-compatible iPad, same Apple Account + 2FA
- Wi‑Fi and Bluetooth on (both devices); USB cable optional but recommended
- A temporary monitor for first-time pairing

## 2. Pair Sidecar once

1. Attach a monitor, keyboard, mouse.
2. Control Center → Screen Mirroring → select your iPad (or System Settings → Displays).
3. Confirm the desktop appears on the iPad.
4. Disconnect Sidecar from Control Center (our agent will reconnect later).

On the iPad: **Settings → Display & Brightness → Auto-Lock → Never** while it is your Mac display. Keep it powered (USB to the Mac is ideal).

## 3. Install MacIPadDisplay

```bash
cd mac-ipad-display
./Scripts/install.sh
```

Edit config:

```bash
open "$HOME/Library/Application Support/MacIPadDisplay/config.json"
```

Important keys:

| Key | Purpose |
| --- | --- |
| `iPadName` | Substring of the iPad name from `mac-ipad-display list` |
| `wiredFirst` | Try USB Sidecar before Wi‑Fi |
| `lockAfterFirstConnect` | Lock Mac right after first Sidecar connect (recommended with auto-login) |
| `ntfyURL` | e.g. `https://ntfy.sh/your-long-random-topic` |
| `ntfyToken` | Optional ntfy access token |
| `barkURL` | Alternative: `https://api.day.app/YOURKEY` |
| `appriseURLs` | Optional list of Apprise URLs instead of/in addition to ntfy/Bark |

Test:

```bash
mac-ipad-display list
mac-ipad-display connect --wait 30
mac-ipad-display notify-test
```

## 4. Unattended boot (required for “no screen at login”)

**FileVault and automatic login cannot both be on** (Apple’s rule).

### Recommended for home Mac mini

1. System Settings → Privacy & Security → **FileVault → Turn Off**
2. System Settings → Users & Groups → **Automatic login** → choose your user
3. System Settings → Energy → **Start up automatically after a power failure** (wording varies by macOS)

Then cold boot with no monitor:

1. Mac reaches desktop alone  
2. LaunchAgent starts MacIPadDisplay  
3. Wake/unlock iPad → Sidecar connects within seconds  
4. If `lockAfterFirstConnect` is true, the Mac locks (iPad shows lock screen)

### If you keep FileVault

You must type the password **blind** on a keyboard ~40s after power-on (or use `sudo fdesetup authrestart` for planned reboots only). Sidecar still only starts after the session exists.

## 5. iPhone safety notifications

### ntfy (default)

1. Install **ntfy** from the App Store on your iPhone  
2. Subscribe to your private topic (same as `ntfyURL`)  
3. Prefer a long random topic name; optionally enable auth and set `ntfyToken`  
4. For sensitive alerts, [self-host ntfy](https://github.com/binwiederhier/ntfy) instead of ntfy.sh  

```bash
mac-ipad-display notify-test
```

### Bark (alternative)

1. Install **Bark** on iPhone, copy your key URL into `barkURL`  
2. `mac-ipad-display notify-test`

### Login / unlock alerts

```bash
./Scripts/install-hooks.sh
```

Install [loginwatcher](https://github.com/RamanaRaj7/loginwatcher) so `~/.login_success` / `~/.login_failure` run on unlock attempts. You will get iPhone pushes when someone unlocks (or fails to unlock) the Mac.

Events the agent itself sends:

- Session started (agent launch)
- Sidecar connected / disconnected
- Monitor stand-aside / resume
- Reconnect exhausted (if `maxConsecutiveFailures` > 0)

## 6. Restart test (before you trust it)

1. Unplug the monitor while the Mac is running → iPad should take over within seconds  
2. Restart with monitor unplugged → wake iPad → wait ~15s  
3. Confirm iPhone got session + connected notifications  
4. Keep Screen Sharing or a spare HDMI cable as a way back in  

## 7. Optional: iPad Shortcut assist

On the iPad, create a Shortcut that runs **when unlocked**:

- **Run script over SSH** to the Mac: `~/.local/bin/mac-ipad-display connect --wait 5`  
  or hit a tiny local HTTP helper if you add one later  

This makes “wake iPad → connect” push-assisted instead of Mac-only polling.

## 8. Troubleshooting

| Symptom | Check |
| --- | --- |
| No devices in `list` | Same Apple Account, BT/Wi‑Fi on, iPad unlocked since reboot, Handoff on |
| Connect fails “locked/asleep” | Wake and unlock the iPad |
| App runs but never connects headless | Auto-login on? FileVault off? Agent loaded? `launchctl print gui/$UID/com.personal.mac-ipad-display` |
| No iPhone push | Topic/token, network, `notify-test`, logs in `~/Library/Logs/MacIPadDisplay/` |
| Broken after macOS update | Private SidecarCore selectors may have changed — check logs for `SidecarDisplayManager class not found` |

Logs:

```bash
tail -f ~/Library/Logs/MacIPadDisplay/mac-ipad-display.log
```
