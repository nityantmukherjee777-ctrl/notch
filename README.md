# Notch

A native SwiftUI / AppKit menu-bar app built for Intel and Apple silicon Macs running macOS Ventura 13 or later. The universal app uses a floating capsule on screens without a physical notch. See [COMPATIBILITY.md](COMPATIBILITY.md) for feature limits and hardware validation status.

## Run

This repository currently contains source code. A public DMG and release feed
are not published yet; there is no downloadable public binary to install.
To run from source, follow the build and signing instructions below.

Clone the project with:

```sh
git clone https://github.com/nityantmukherjee777-ctrl/notch.git
cd notch
```

Open `dist/Notch.app`. On first launch, the settings window opens. The app lives in the menu bar; it does not add a Dock icon.

- Click the black notch, use the menu-bar **Open Notch** command, or press **⌥⌘N**.
- Hover for a short peek. Move away to close a hover-opened panel. Click-opened panels stay open until you click elsewhere or press Escape while the panel is focused.
- Swipe left/right with two fingers to switch enabled widgets, or use the icon toolbar. Swipe up/down in the compact media player to select another available media source. Click the artwork to open lyrics; the back arrow returns to the player. Vertical gestures scroll the lyrics in the lyrics view.
- Select an activity along the top of the expanded widget panel. Activity switching preserves playback, countdowns, Keep Awake, and usage tracking.
- Open **Settings → Tracked Apps** to enable Codex. Tracking defaults off and uses your existing Codex sign-in.
- Connect Spotify or Apple Music from the player’s connect buttons or Settings → Tracked Apps. Browser media is detected automatically when it is published to macOS Now Playing. macOS asks for Automation access. If denied, you can enable Notch under **System Settings → Privacy & Security → Automation**.
- On macOS 14.2+, the first playing track shown in the compact notch, or first hover over the playback scrubber, asks for **System Audio Recording Only** so the visualizer can follow the actual music. After granting it, use macOS's **Quit & Reopen** action once. Earlier systems keep the normal playback slider and a static compact indicator, without asking for audio capture. Notch never asks for screen or microphone recording.
- Keep Awake starts off on every launch. Launch at login also defaults off.

Builds now require a persistent signing identity instead of silently using ad-hoc signing. See [LOCAL_SIGNING.md](LOCAL_SIGNING.md) for the one-time local setup. The old ad-hoc app used a build-specific code hash, so rebuilding could invalidate privacy approvals. Moving to the retained identity may require one final approval for the newly signed app. Keep launching the same `dist/Notch.app` (or one installed copy), and retain the signing key for future updates. This remains a personal build, not a notarized public release.

If audio capture fails, Notch pauses attempts across relaunches. After checking **System Audio Recording Only**, use **Settings → Tracked Apps → Retry visualizer**, then play a track in the compact notch or hover the playback slider. It does not reset macOS privacy grants. Keyboard HUD access is checked without prompting at launch, recovered after sleep/session changes, and retried if the event tap becomes invalid. Only the explicit Accessibility button requests permission.

## Build and test

Requires Swift 6 command-line tools and a macOS 14.2+ SDK; a full Xcode installation is not required. The current toolchain uses the compatible macOS 15.4 SDK. The first build downloads the pinned Sparkle 2.10.0 package through SwiftPM, which verifies its binary checksum. Subsequent builds use the cached dependency. The BSD-licensed media adapter source is vendored and compiled locally.

With the retained personal certificate, macOS cannot load Sparkle under library validation because that certificate has no Apple Team ID. The packager requires explicit consent to a personal-build exception: after approval, use `NOTCH_ALLOW_LOCAL_SPARKLE=1 ./scripts/build.sh`. This exception is rejected for verified public builds. See [UPDATES.md](UPDATES.md) for the scope. Apple-signed builds need no exception.

```sh
./scripts/build.sh
./scripts/test.sh
# Only when the installed CLT cannot load Testing.framework:
python3 scripts/test-compatible.py
python3 scripts/test-update-configuration.py
python3 scripts/test-signing-policy.py
python3 scripts/check-compatibility.py dist/Notch.app
```

The build compiles separate arm64 and x86_64 executables and combines them into `dist/Notch.app`, generates its icon locally, and verifies its signature. It checks every bundled native executable for both architectures and a deployment target no higher than macOS 13 before replacing the existing app. For a debug bundle, run `./scripts/build.sh debug`. Build caches stay in `.build`. The test script handles the Swift Testing framework location in Apple's command-line-only toolchain. `--disable-sandbox` disables SwiftPM's nested package-manifest sandbox, which cannot run inside some hosted development sandboxes; it does not grant the app additional permissions.

## Included

| Feature | Behavior |
| --- | --- |
| Native surface | Opaque black with no border or window shadow, rounded lower corners and curved shoulders, measured idle height, a fixed-window reveal with 280 ms expansion / 200 ms collapse, pointer-dwell hover, immediate keyboard access, display changes and a floating fallback; regular tools use a compact 520-point surface while lyrics alone expands to an 820-point cinema view |
| Music | Spotify / Apple Music desktop scripting plus macOS Now Playing for supported browsers/apps, artwork, source selection, transport, seeking, compact playback bars, hover player and click-to-open lyrics |
| Lyrics | Synced lyrics from LRCLIB on demand, plain-text fallback, instrumental / unavailable / offline states, full-canvas blurred artwork, a single persistent back control, compact rounded text rhythm, hidden scroll chrome, timestamp seeking and a small in-memory cache |
| Brightness and HUDs | Built-in display brightness slider, compact volume / brightness feedback, optional exclusive hardware-key HUD while running, independent settings switches |
| Timer | Custom 1–1,440 minute countdown, presets, name, pause / resume, persisted deadline and completion feedback |
| Keep Awake | Direct toggle, optional duration, macOS idle display-sleep assertion, release on disable, expiry, or app exit |
| Battery | Internal battery percentage and charging status |
| Bluetooth | AirPods and recognized Apple/Beats headsets get a brief inline connection display with reported battery charge; other Bluetooth devices stay quiet; no BLE scanning or connection history |
| Audio | Default output volume and mute when supported by the device; hardware-controlled devices show an unavailable state |
| Codex | Independent quota bubble, remaining percentage, reported window duration, reset countdown, freshness, connection errors, tracking toggle |
| Settings | Feature toggles, tracked apps, favorite order, accent / spacing, pinned primary activity, display, global shortcut, launch at login |
| Updates | Sparkle 2.10.0, Check for Updates in the menus and Settings → About, hourly checks and automatic download/installation enabled by default with settings to turn them off; inactive until a signed release feed is configured |

Playing music takes the main notch by default. Paused music no longer keeps the compact media wings visible; the notch falls back to another live activity or blends into the physical cutout. You can still deliberately open it to resume playback. Timer and recently active Codex keep their own ordered circular bubbles when another activity is primary. The Codex circle appears when local session files are written while Codex is running, or when its connection reports active work or quota consumption. A metadata-only file-event watcher detects local writes without waiting for the 60-second quota refresh; it never reads session contents. The circle returns to the notch after 5 minutes without detected activity. Simply refreshing quota or focusing Codex does not extend that time. Session writes indicate local work, not a precise token counter; quota remains account-wide. Every activity bubble stretches out from the adjoining black surface, pinches apart, and settles into its stable position. When an activity ends, the bubble merges back with the same connected motion. Reduce Motion skips both transitions. Usage remains accessible from the toolbar even when the circle is hidden. They sit directly beside the notch, aligned to its compact row, with a four-point gap between window frames. Pinning timer or Codex keeps active music available in a circle. A constrained display uses a circular overflow menu. Click a circle to open its details.

Full-screen suppression uses public window bounds and frontmost process metadata; no screen recording or Accessibility permission is needed for that check. Keyboard HUD replacement separately uses Accessibility access. It conservatively treats a frontmost window covering the entire selected display as full screen. Deliberate click and shortcut access remain available. Passive changes never activate the app. Reduce Motion disables movement, Increase Contrast follows the native accessibility environment, and the notch surface is always opaque. Native settings materials follow system accessibility preferences.

The default appearance is neutral white on black. This revision replaces the old default mint accent; optional accents remain in Settings. The collapsed window now matches the measured physical notch height, without the old seven-point extension.

The five playback bars in the collapsed notch retain their compact shape but now follow five bands of the same live spectrum as the expanded scrubber. Their color comes from the album artwork; predominantly black artwork uses gray for legibility. A private Core Audio tap maps a logarithmic bass-to-treble spectrum with independent per-band attack and decay. macOS asks for **System Audio Recording Only**, not screen recording or microphone access. The tap stops when the compact music bars are hidden and the media scrubber is not hovered; it never records, stores or uploads audio. With Reduce Motion, the bars update without transition animation. The main window stays fixed during the transition: SwiftUI animates the black surface and clipping mask while the media layout keeps its final dimensions. Empty canvas space passes pointer events through to the underlying app. Satellite-window motion uses a display link only while moving.

**HUD scope:** with “Use Notch for volume and brightness keys” enabled and Accessibility access granted, Notch handles the five volume, mute and brightness hardware keys and consumes successfully handled events so Apple’s keyboard HUD does not also appear. It tries the HID event tap first and falls back to the session tap. Feedback remains visible in the footer when a tool is already open. Quitting, disabling replacement, or losing access removes the event tap and restores normal system handling. Unsupported controls and modifier shortcuts pass through to macOS. Without access, replacement mode leaves macOS in control and waits; explicit mirroring mode can display both HUDs. No system HUD process or persistent macOS setting is modified. Brightness uses an isolated DisplayServices adapter and gracefully becomes unavailable on unsupported displays; arbitrary external-monitor DDC control is not included.

Every regular tool uses the same top icon toolbar and stable 560 × 234 point surface on a display with a 32-point notch inset; lyrics alone expands to 820 × 440. The lyrics view removes the widget and utility controls, retaining one back arrow over blurred artwork. Its scroll indicator is hidden while native trackpad scrolling remains available. Click a synced lyric line to seek to its timestamp; plain lyrics remain read-only. Album covers use tighter corners and a restrained artwork-coloured reflection, and clicking the cover is the only lyrics entry point. Sliders use a continuous track without a thumb while retaining a larger invisible drag target and keyboard accessibility. The playback track crossfades in place to up to 112 fine, rounded white spectrum bars that rise from one baseline while hovered; quiet bands become dots and the bars never connect into a filled block. Seeking holds its destination optimistically until the media service confirms the new position, preventing a stale reading from bouncing the track backwards. Timer and Codex content use wider centered layouts instead of stretching to the panel edges. Hover detection samples the actual pointer position as well as mouse events, so a missed boundary event no longer loses the reveal. Expanded content remains mounted until the 200 ms collapse completes, and its temporary hit region follows the moving surface so button presses are not lost during transitions.

## Data and services

`NotchCore` contains the shared activity, layout, persisted countdown, preferences, and quota interpretation models. `PanelController` owns window placement and interaction. `AppState` connects the independent music, timer, power, battery, Bluetooth, audio, and Codex services to SwiftUI.

Settings and timer state are stored in the app's local preferences domain (`local.notch.mac`). No analytics, clipboard history, camera access, microphone access, or app cloud account is included. Artwork requests go to the HTTPS URL supplied by Spotify; Apple Music artwork is read through its scripting interface. Clicking lyrics sends track title, artist, album and duration to LRCLIB over HTTPS. Lyrics are cached only in memory, with a 30-track bound. System audio is sampled locally only while the playback scrubber is hovered. A short-time frequency spectrum drives logarithmic bass-to-treble bars, with fast attack and smooth release. A rolling 2,048-sample analysis window is overwritten continuously and discarded when the tap stops; no audio is saved.

Codex starts a local `codex app-server proxy` connection, falling back to its own `codex app-server --listen stdio://` child when a running daemon is unavailable. It initializes the documented protocol, reads `account/rateLimits/read`, and listens for `account/rateLimits/updated`. It does not start model turns or consume a usage reset. It stops its child process and all refresh scheduling when tracking is disabled. It does not terminate the Codex desktop app or daemon.

Usage refreshes on enable, opening details, wake, the reported reset deadline, and approximately once a minute while enabled. The Codex bucket is used when multiple quota buckets are reported. Missing fields display as unavailable, never zero usage. Readings older than three minutes or past their relevant reset are marked stale. Values are percentages of subscription quota, not invented token counts. Authentication remains managed by Codex; Notch never reads or displays credentials.

Music scripting runs on a utility queue with bounded Apple-event timeouts. A closed player is not launched by polling. Connect is explicit. Music refreshes every five seconds when compact and every second while its details are open. Battery uses power-source notifications for its status; power connection no longer opens a transient card. Bluetooth registers for connection notifications. Only recognized Apple audio headsets briefly replace the compact notch's contents for four seconds, without adding a floating card or changing its shape. Ordinary headphones, speakers, keyboards, mice, and unidentified devices stay quiet and do not trigger a battery query. Recognition uses cached public PnP vendor and headset-class data when available, with an AirPods/Beats name fallback if identity metadata is missing. Known conflicting vendor/device-class information prevents the fallback; renamed Apple headsets can use generic headphone artwork when the exact model is unavailable. Notch does not change pairing, audio routing, automatic switching, or native notification settings. Its ring represents the connected device's reported battery level: the lower earbud when both are reported, otherwise a single available earbud or main battery. The case never determines the earbud ring. Levels at 20% or below use amber, and 10% or below use red. Unknown charge shows a neutral connection check, with “Battery unavailable” in the help text; hovering also reveals reported left/right/case levels. A bounded asynchronous System Information query runs on connection with at most one delayed retry, stops on disable/expiry, and never polls at idle. Only the matching connected device is used; disconnected cached readings are ignored. macOS may request Bluetooth access when that switch is enabled. Audio uses Core Audio change listeners with a three-second fallback; brightness checks the display every 750 ms without spawning a process; the timer only ticks while running. System media uses an event stream from the bundled adapter and stops with music tracking.

## Browser media coverage

macOS publishes one system Now Playing session at a time. Notch combines that session with independent Spotify and Apple Music readings; the source icons and vertical swipes select among those available sources without pausing them. Chrome/Brave YouTube and other pages work when the browser publishes media metadata. A muted page may not become the system’s active session. Independent enumeration/control of every browser tab still belongs to the planned browser extension. A missing system session is not fabricated from a browser tab title.

The isolated MediaRemote adapter and DisplayServices integration use private macOS APIs, so OS updates can affect them. See [THIRD_PARTY.md](THIRD_PARTY.md) for pinned source and license details.

## Release review

Sparkle is embedded and signed in build 21. This build has no release feed or update key, so update controls remain disabled and no update requests are made. GitHub hosting and `.dmg` packaging are deferred. See [UPDATES.md](UPDATES.md) for the configuration needed when releases begin. The existing bundle identifier, signing identity and privacy grants are retained.

See [AUDIT.md](AUDIT.md) for measured results and checks requiring hands-on hardware or account validation. [PRODUCTION.md](PRODUCTION.md) describes the direct-distribution signing, notarization and release gate. The next features are listed in [BACKLOG.md](BACKLOG.md) with planned version numbers. Shelf, clipboard history and calendar remain unimplemented in this build.

Protocol reference: [Official Codex app-server documentation](https://learn.chatgpt.com/docs/app-server).

## License

The original app source and project artwork are **all rights reserved**; this
is a public source repository, not an open-source license grant. See [LICENSE](LICENSE).
Third-party components retain their own licenses and notices in [THIRD_PARTY.md](THIRD_PARTY.md).
