# Auto-login helper notes

MacIPadDisplay does **not** silently change FileVault or automatic login.
Configure those yourself in System Settings (see SETUP.md), same honesty model as SideMini’s confirmation step.

To inspect current state on a Mac:

```bash
# FileVault
fdesetup status

# Automatic login is visible in System Settings → Users & Groups.
# There is no supported public CLI to enable it on modern macOS without
# writing protected preferences; use the GUI.
```

After enabling auto-login, keep `lockAfterFirstConnect: true` in config.json so an unattended boot does not leave an unlocked desktop on the iPad.
