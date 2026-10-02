# Dependencies and data sources

## Sparkle

- Source: https://github.com/sparkle-project/Sparkle
- Pinned release: 2.10.0; revision `eef1a539a373c1f1a320624b1130fc5de7b2e100`, recorded in `Package.resolved`.
- SwiftPM binary archive SHA-256: `17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959`.
- Copyright © Sparkle Project contributors; the upstream distribution's licence and notices are retained as `Contents/Resources/Sparkle-LICENSE`.
- Official binary framework is embedded with its helpers, then signed inside out with the app's selected signing identity. No Sparkle source or helper entitlements are modified.
- Automatic updates require an HTTPS appcast and an Ed25519 public key in the signed app. The current local build has neither and does not start the updater. See [UPDATES.md](UPDATES.md).

## MediaRemote Adapter

- Source: https://github.com/ungive/mediaremote-adapter
- Pinned commit: `73f14ab1568371e6e3c44063f21c34c5e2712c4d`
- Copyright © 2025 Jonas van den Berg; BSD 3-Clause license, retained in `Vendor/mediaremote-adapter/LICENSE` and the built bundle.
- Source is compiled locally with Apple’s command-line compiler. The bundled Perl entry point uses the macOS MediaRemote framework for the current system media session. No browser extension, audio capture, login, or remote service is used by this adapter.
- Upstream source is unmodified. App-side lifecycle, parsing and bounded commands live in `SystemMediaService.swift`.

## Lyrics

- LRCLIB API: https://lrclib.net/docs
- Fetched on demand when the user opens lyrics. Track title, artist, album and duration are sent. No account or token is required. Availability and timestamp accuracy depend on the catalog.
- Lyrics are not bundled with this source repository; the in-app view attributes LRCLIB. Cache is memory-only.

## Development guidance

[Stats’ Bluetooth reader](https://github.com/exelban/stats/blob/master/Modules/Bluetooth/readers.swift) was consulted to confirm the battery field names in Apple's `system_profiler SPBluetoothDataType -json` output. The app's bounded event-only reader and validation code are original; no Stats source or runtime dependency is bundled.

[AvdLee’s SwiftUI Expert Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill), installed in the user’s Codex skills folder, informed native layout, scoped animation, and view composition. It is a development aid, not a runtime dependency.

The Bluetooth card's transparent earbud and headphone illustrations were generated for this project using OpenAI ImageGen; no stock image is bundled.

Build 13 replaces the earbuds with a reference-guided render and uses them directly within the notch. The saved asset is `Resources/DeviceEarbuds.png`; generation used the built-in ImageGen tool. Final prompt:

> Create ONLY a transparent product-icon asset of the two AirPods Pro earbuds visible on the LEFT in the supplied Dynamic Island screenshot. Closely match their real proportions, orientation and understated gray-white lighting: small oval housings, long slim vertical stems, one turned slightly sideways with silicone tip, the other facing forward with dark oval vent. They stand side by side with a little space and no overlap, evenly sized. Clean realistic 3D rendering, soft silver-gray shading, restrained specular light. Tightly frame the pair centered in a square canvas with 8% transparent margin. Output has fully transparent background. Do NOT include the black pill, green ring, scene, lettering, charging case, drop shadow, halo, bloom, glow, reflections outside the earbuds, or giant rounded heads. This image must remain legible as a 28-pixel native macOS status icon.

[Varun Vachhar’s metaball explanation](https://varun.ca/metaballs/) was a motion reference. The app's continuous signed-distance contour implementation is local Swift code, with no runtime library or copied example code.
