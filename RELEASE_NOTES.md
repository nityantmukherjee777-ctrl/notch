# v1.1.0 build 22 — NotchHarbor and installation setup

- Renamed the app and GitHub repository to NotchHarbor, retaining the bundle identifier, executable and signing requirement.
- Added first-launch Setup with separate Accessibility, music Automation and optional audio controls. New installs enable audio visualization explicitly; existing successful capture remains enabled.
- Mounted/translocated copies ask users to install before starting services.
- Prepared a local/test drag-to-Applications DMG with instructions and verified contents. No public binary or feed is published; this personal build is not notarized.
- Reviewed the complete public source history and retained a default-deny file allowlist.
- Validation: 69 app regression checks and 7 update/signing checks passed; universal binary metadata and retained signatures passed. Fresh-Mac and older-hardware testing remain outstanding.

# v1.1.0 build 21 — older-Mac compatibility

- Lowered the deployment target to macOS Ventura 13.0 and packaged Intel and Apple silicon executables in one universal app, including the media adapter and Sparkle helpers.
- Added a Ventura-only animation clock and change-observation fallback. Newer systems retain the existing animation implementation.
- Gated audio capture to macOS 14.2+ with a clear settings explanation and no unavailable capture attempts or permission prompts. Earlier versions retain the playback slider and static compact bars.
- Added a package gate checking architectures and deployment targets of every embedded native executable. Older-hardware runtime validation remains required before public release.
- Keep Awake remains unchanged; closed-lid override is deferred. Release hosting and feed activation remain deferred until the repository exists.

## Build 20 — Sparkle integration

- Added Sparkle 2.10.0, Check for Updates in both menus, and update settings in About.
- Configured future signed releases for hourly checks, automatic background downloads and installation on quit/relaunch, with user controls to disable them. Archive verification happens before extraction; signed appcasts and release notes are required; system profiling is disabled.
- GitHub hosting, update signing keys and DMG packaging are deferred. Without a configured feed and public key, the updater stays inactive and makes no requests. The retained personal signer requires an explicitly approved local-only library-validation exception to load Sparkle; verified public builds reject that exception.

## Build 19 — Spotify playback fallback

- Preserved Spotify and Apple Music system Now Playing sessions when desktop scripting returns no track. Dedicated desktop readings remain preferred without duplicate source buttons. System fallback retains transport controls and artwork.

## Build 16 — quieter Bluetooth connections

- Limited the connection display to recognized Apple audio headsets, including AirPods and recognized Beats. Ordinary Bluetooth connections stay quiet instead of showing generic artwork or an icon-and-name confirmation. The settings switch now names AirPods and Beats.
- Added cached public vendor/headset-class recognition, with branded-name fallback only when identity metadata is missing. Renamed Apple headsets can still display without inventing an exact model. Beats speakers remain quiet. Battery queries run only for eligible displays. Native pairing, routing, automatic switching, and notification behavior are unchanged.

## Build 15 — connected-device battery

- The connection ring now represents reported battery charge. AirPods use the lower reported earbud charge; case charge stays separate in help text. Low charge uses amber/red. A neutral check indicates connection when charge is unavailable, rather than a full battery circle.
- Battery readings come from a bounded, asynchronous System Information query only on connection, with one short retry. Disconnected readings are ignored. Disabling the feature or expiry stops the query. Other earbuds/headphones use their matching illustrations, while speakers, keyboards, mice, and unknown devices use system symbols.

## Build 14

- Reduced the inline earbud artwork by 12.5%, keeping the notch geometry, ring, and animation unchanged. The owner confirmed the duplicate native connection alert no longer occurs; notification handling is unchanged.

## Build 13 — reference-matched connection and fluid bubble motion

- Refined the inline connection display with slim, softly shaded earbud artwork, a smaller unadorned green ring, and a restrained fade and lift. Removed the glow, checkmark, exaggerated rotation, and fixed 82% arc. The ring draws once to completion to indicate connection; it is not a battery reading.
- Replaced the bubble's discrete outline stages with a continuous smooth-union contour. The neck narrows into a split, the same path reverses on return, and movement stays monotonic. Content fades before merging and appears as division finishes. The temporary silhouette stays behind existing activities.

## Build 12

- Reworked every activity bubble entrance and return as a connected, pinching cell-division silhouette with a single short display-synchronized animation. Reduce Motion skips movement.
- Removed the transient power-connected card. The battery percentage and charging state remain available.
- Added an optional four-second Bluetooth connection moment inside the existing compact notch. Transparent 3D earbuds or headphones appear at left, with an animated green connection ring at right; other devices use a symbol. No separate black pill or floating card appears. Duplicate profile events are suppressed and no connection history is kept. The ring indicates connection, not battery percentage.

## Earlier v1.1 changes

- Timer, Codex, music, and overflow bubbles now use the connected division motion on entrance and the matching merge motion on return. Reappearing bubbles retarget from their current position, and Reduce Motion skips the effect.
- Moved the Open Media App icon from the shared toolbar into the media player next to its source controls.

- Codex bubbles react to local session-write events without waiting for quota changes, preserve the five-minute inactivity timeout, and stop observation when tracking is disabled. No session contents are read.
- Added a connected cell-division entrance: the black surface stretches into a circle, pinches apart, and settles beside the notch. Interrupted transitions clean up their temporary bridge; Reduce Motion bypasses it.

- Balanced the compact visualizer's range: audible audio supplies a visible base height, positive transients add beat lift, and dips no longer subtract the bars down to dots. Sustained loud audio retains room for peaks.

- Polished the compact audio bars with round end caps at every height, quick beat attack and softer release, more headroom for loud passages, and interruptible album-color transitions.

- The compact five-bar music indicator now follows the live system-audio spectrum, sharing the scrubber's capture session. It retains its shape and uses the album's representative color, or gray for predominantly black artwork.
- Audio capture now stops when neither the compact indicator nor the hovered scrubber needs it. The media-app shortcut appears only on the media page.

- Retained code-signing identity for personal builds; updates no longer rely on a changing ad-hoc code hash.
- Fixed duplicate-HUD timing after successful device writes and keyboard connection recovery after sleep/session changes.
- Audio setup failures no longer retry automatically on each hover/relaunch; explicit retry lives in settings.
- Bounded HTTPS downloads while streaming, validated redirects, disabled persistent network caches/cookies, and downsampled artwork with image-size limits.
- Rejected or bounded malformed media times, lyrics timestamps, quota resets and saved layout/timer values.
- Stopped Codex pipe callbacks on EOF; bounded long reset scheduling.
- Added Hardened Runtime signing and a public-binary release gate.
- Added a clean source archive exporter that excludes personal documents, binaries, caches and signing material.

- Restored Codex discovery for the current ChatGPT/Codex application layout, including moved apps and older installations.
- Codex bubbles now follow detected consumption, retire after 5 minutes without activity, and preserve other bubbles during entrance/exit motion.
- Replaced the split percentage layout with one fitted label, including 100%, and restrained the bubble highlights.
- Restored the original lyrics layout and kept its panel receptive to pointer clicks while open; the back arrow decoration ignores hit testing, and the panel routes clicks on its screen area to the back action.

Public release is still gated by Developer ID signing/notarization, publisher
metadata/licensing, a matched Swift toolchain, and the hardware/clean-Mac checks
in PRODUCTION.md. Dictation and live interview assistance are roadmap items,
not features in this build.
