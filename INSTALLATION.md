# Install NotchHarbor

The repository currently publishes source. The prepared build 22 DMG is a
local/test artifact; no public binary release or update feed has been published.

1. Open the DMG and drag **NotchHarbor** onto **Applications**.
2. Eject the disk image, then open the installed app from Applications.
3. Use the menu-bar icon → **Settings → Setup**. There is no Dock icon.
4. Enable only the features you want and approve their macOS prompts.

Do not launch everyday copies from a mounted image or Downloads. Mounted and
translocated copies stop before starting services and ask you to install first.
The rename retains the bundle identifier, executable and signing requirement;
it does not deliberately reset existing privacy grants. Permissions remain
controlled by macOS. Use the same publisher's signing key on future updates.

| Permission | Purpose | Setup action |
| --- | --- | --- |
| Accessibility | Volume / brightness hardware-key HUD | Open Accessibility, unlock if asked, enable the Applications copy; click + if missing. Return to Setup to recheck. |
| Automation | Spotify / Apple Music desktop controls | Connect your player, then approve its macOS prompt. Browser Now Playing does not use this grant. |
| System Audio Recording Only | Audio-reactive bars, macOS 14.2+ | Enable live visualizer explicitly. Play media to trigger the macOS prompt. Use Quit & Reopen if offered. After denial, change the grant and choose Retry visualizer. |
| Bluetooth | Optional Apple headset connection display | Enable under Activities if wanted. |

Normal music controls work without audio capture. System keyboard HUDs work
without Accessibility. Setup never grants permissions automatically, resets TCC,
or collects a microphone recording. If a managed Mac restricts access, its
administrator controls the grant.

## Current signing limits

The owner's current choice is a retained personal certificate, without Apple
Developer membership. This DMG is **not notarized**. On another Mac, a downloaded
copy may be blocked by Gatekeeper. Verify the source and checksum, then use
System Settings → Privacy & Security → Open Anyway if you choose to trust it.
The exact approval varies by macOS version. No security-disabling command is
part of installation. A notarized Developer ID release is the recommended
future path for smoother public installation; source publication does not
require it.

## Build the installation image

After building and signing the app as documented in README:

```sh
python3 -m pip install --target .build/dmg-tools ds-store==1.3.1 mac-alias==2.2.2
python3 scripts/package-dmg.py
```

This creates a compressed local DMG and SHA-256 file in `dist`, with the signed
app, Applications link, instructions and Finder layout. It checks image
integrity, contents, the app signature and both native architectures after
mounting the final image read-only. It neither publishes the image nor configures
an update feed. Build tools and staging files stay outside the source archive.
Fresh-Mac permission approvals and older Intel/macOS hardware still need testing.
