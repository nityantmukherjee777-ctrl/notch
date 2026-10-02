# Compatibility

Build 21 targets macOS Ventura 13.0 and later on both Intel (x86_64) and Apple
silicon (arm64). It does not support Monterey 12 or older. Use a Mac model that
Apple supports on the selected macOS release. This is a build target, not a claim
that every supported Mac model has been physically tested.

| Feature | Availability |
| --- | --- |
| Notch, activities, settings, timer, Keep Awake, lyrics | macOS 13+ |
| Display placement | Physical notch when available; floating capsule otherwise |
| Live audio visualizers | macOS 14.2+; earlier versions retain the playback slider and static compact bars |
| Spotify / Apple Music | Installed desktop app and Automation permission; system Now Playing fallback where available |
| Browser media | Browser must publish a macOS Now Playing session |
| Volume / mute | Audio device must expose writable volume / mute |
| Brightness | Compatible built-in display; external-monitor DDC control is not implemented |
| Keyboard HUD replacement | Accessibility permission and supported volume / brightness controls |
| Codex tracking | A running, authenticated local Codex installation with the app-server protocol |
| Bluetooth connection feedback | Recognized Apple/Beats headsets; reported battery fields may be absent |
| Sparkle | Included universally; inactive until the release feed and public signing key are configured |

On systems without Core Audio process taps, audio capture never starts or
retries, and its permission buttons are hidden. Apple's tap API is available
from macOS 14.2. See [Apple's audio capture documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
Ventura uses a common-mode 60 Hz timer during satellite-window movement;
Sonoma and later use the display's CADisplayLink. Both stop when movement ends.

Keep Awake retains its existing idle-sleep assertion, starts off after launch,
and releases on disable, expiry or quit. Closed-lid sleep override is deferred
at the owner's request. It is not guaranteed by this mode.

## Verification

`scripts/build.sh` packages both architecture slices for Notch and the media
adapter, and embeds Sparkle's universal framework and helpers. Before signing
and installation, `scripts/check-compatibility.py` checks all native executable
slices and their deployment targets against the app's Info.plist minimum.
This verifies packaging metadata, not old-OS runtime behavior.

The regression suite includes an unsupported-audio scenario: active views,
retry, wake and health checks must never invoke capture, even with a saved
permission-failure latch. The latch is retained for a later OS upgrade.

Before a public compatibility claim, test the final signed bundle on an Intel
Mac running Ventura, an Apple silicon Mac on Ventura or Sonoma 14.0/14.1, and
macOS 14.2+ for audio capture. Include clean first launch, menu interaction,
floating placement, media transport/artwork, timer restoration, sleep/wake,
permission denial, HUD keys, Sparkle upgrade and private-adapter availability.
The local smoke test runs on the current Apple silicon Mac; no older Mac or OS
has been runtime-tested in this workspace.
