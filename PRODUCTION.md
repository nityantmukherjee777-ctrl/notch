# Production release checklist

The current bundle is a usable local release. Public distribution should use **direct download**, signed with Developer ID and notarized by Apple. The app intentionally uses isolated private MediaRemote and DisplayServices integrations, Accessibility event taps, and music automation. The Mac App Store requires App Sandbox and public APIs, which conflicts with the current implementation.

## Current release status

The September 29 audit fixes and source package are a release candidate, **not
a notarized public binary**. GitHub source hosting and GitHub Releases are the
intended distribution route. A GitHub-hosted `.app` has the same Developer ID
and notarization requirements as any other direct download; hosting alone does
not resolve Gatekeeper or permission onboarding.

Implemented: retained local signing identity, Hardened Runtime build support,
bounded network/media input, regression checks, staged package replacement,
source-only export, and a fail-closed public-binary check. See AUDIT.md for the
findings and evidence. Source hosting is configured at
[nityantmukherjee777-ctrl/notch](https://github.com/nityantmukherjee777-ctrl/notch).
No binary release or update feed has been published.

Publisher decisions still required: owned bundle identifier, copyright/contact,
Developer ID Application credentials. The owner selected all rights reserved
for original app source and artwork; third-party licenses remain intact. Do not upload the
personal signing keychain. There are unrelated personal documents in the local
workspace: publish `dist/Notch-source.zip`, not an archive of the entire folder.

## Reproducible checks and packaging

```sh
./scripts/test.sh
# Explicit fallback for the installed CLT's incompatible Testing.framework:
python3 scripts/test-compatible.py
python3 scripts/source-release.py
```

The fallback executes the existing simple test bodies with ordinary Swift
assertion helpers and serial async invocation. It is not a successful Swift
Testing run. Before public launch, run the original suite with a matched Xcode
toolchain/SDK and execute the hardware checks below on a second Mac.

For an approved public identity, build with `NOTCH_PUBLIC_RELEASE=1` and
`NOTCH_SIGNING_IDENTITY` set to the Developer ID Application identity. This
requires a secure timestamp and rejects local/ad-hoc signing. Then submit the
archive with Apple's `notarytool` using credentials stored in Keychain, inspect
the accepted result, staple with `xcrun stapler staple`, and run:

```sh
python3 scripts/check-public-release.py dist/Notch.app
```

Publish the final stapled archive with its SHA-256 checksum and RELEASE_NOTES.md
only after the gate and functional checklist pass. Sparkle 2.10.0 is now integrated;
GitHub hosting and DMG packaging are deferred. Configure and test the signed feed
as described in [UPDATES.md](UPDATES.md) before enabling public update rollout.

## Product identity

- Choose the final product name and a stable reverse-domain bundle identifier owned by the publisher. Replace `local.notch.mac` before the first public build.
- Set the publisher name, copyright, semantic version, monotonically increasing build number, support URL, privacy-policy URL, and release notes.
- Keep the bundle identifier stable after release so Automation, Accessibility, login-item, updater, and preference identity remain consistent.

## Apple signing and notarization

- Use an active Apple Developer Program team and a **Developer ID Application** certificate.
- Build with the matching current Xcode toolchain and macOS SDK. Resolve the local Swift compiler / SDK patch mismatch before calling the build reproducible.
- Sign the embedded MediaRemote adapter first, then the app, with Hardened Runtime, a secure timestamp, and only the entitlements the app needs.
- Verify the final app with `codesign`, Gatekeeper assessment, and Apple’s system policy checks.
- Package the signed app as a ZIP or DMG, submit it with `notarytool`, inspect the notary log, staple the accepted ticket, and verify the stapled package.

Apple’s references:

- [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## First-run experience

- Explain Automation and Accessibility before opening the relevant System Settings page.
- Detect denial, stale permission records, unsupported brightness, and hardware-controlled audio without trapping the user.
- Provide a short permission-repair flow for rebuilt or relocated apps.
- Add an in-app diagnostics page that reports app version, macOS version, display, current media source, permission state, and service availability without exposing credentials.

## Release quality gate

- Run unit and state-restoration tests with the final Xcode toolchain.
- Verify the universal package with `python3 scripts/check-compatibility.py dist/Notch.app`, then test Intel and Apple silicon on the older OS versions listed in [COMPATIBILITY.md](COMPATIBILITY.md). Binary deployment metadata alone does not prove runtime support.
- Test a quarantined download on a clean macOS user account and a second Mac. Verify first launch, Gatekeeper, permission onboarding, relaunch, update, and uninstall.
- Test built-in and external displays, full-screen apps, display changes, sleep/wake, multiple audio outputs, unsupported volume, and rapid hardware-key repeats.
- Test Spotify, Apple Music, supported browser media, paused/ended sessions, artwork failure, missing lyrics, plain lyrics, synced seeking, and offline operation.
- Test simultaneous music, timer, Keep Awake, and Codex usage; confirm switching pages does not interrupt them.
- Profile idle CPU, memory, wakeups, animation hitches, and service polling in the final signed build. Keep the original below-one-percent idle CPU target.
- Verify VoiceOver labels, keyboard navigation, Reduce Motion, Increase Contrast, and reduced transparency.

## Distribution and maintenance

- Ship a notarized DMG or ZIP from an HTTPS website with a checksum and release notes.
- Sparkle verifies archive signatures before extraction and requires a signed feed. Test a real older-to-newer upgrade, tampered archive/feed rejection, cancelled/offline updates, relaunch, and permission/settings/timer preservation before enabling automatic rollout.
- Add opt-in crash reporting only if a privacy policy explains it; the current app collects no analytics.
- Publish support, privacy, third-party licence, known-issues, and uninstall instructions.
- Keep the private adapters isolated and covered by a macOS beta compatibility check because an OS update can change them.

## Information needed from the publisher

Before producing the public package, confirm the final app name, an owned domain for the bundle identifier, the publisher/copyright name, Apple Developer team access, and whether updates should be automatic or manual.
