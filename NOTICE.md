# Third-party notices

## SidecarCore bridging

MacIPadDisplay talks to Apple’s private `SidecarCore` framework at runtime (`dlopen`).
There is no public API for programmatic Sidecar connect.

Patterns for `SidecarDisplayManager` connect/disconnect/list and wired `SidecarDisplayConfig`
transport were adapted from:

- [say-michael/sidecar-connect](https://github.com/say-michael/sidecar-connect) (MIT)
- [Ocasio-J/SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher)

## Notification backends (optional, external)

- [binwiederhier/ntfy](https://github.com/binwiederhier/ntfy)
- [Finb/Bark](https://github.com/Finb/Bark)
- [caronc/apprise](https://github.com/caronc/apprise)
- [RamanaRaj7/loginwatcher](https://github.com/RamanaRaj7/loginwatcher)

These are not bundled; configure URLs in `config.json` / install hooks separately.

## Disclaimer

“Sidecar”, “iPad”, and “macOS” are trademarks of Apple Inc. This project is not
affiliated with Apple or with SideMini.
