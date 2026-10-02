# Security

Notch is an unsandboxed macOS menu-bar app. Accessibility is used only for its
shortcut/HUD integration; system audio is sampled only while compact playback
bars are visible or the media visualizer is hovered during playback.
It does not request microphone access, save captured audio, or add analytics.
The app can launch a Codex executable selected by its owner. Select only a
trusted installation; selecting an executable is authorization to run it.

Network lyrics and artwork use ephemeral sessions, bounded response buffers,
HTTPS host restrictions (including redirects), and bounded artwork decoding.
Browser/system media metadata and saved settings are treated as untrusted input.
The MediaRemote adapter is vendored at the commit in THIRD_PARTY.md.

This audit is not a guarantee that all vulnerabilities have been found. The
private macOS integrations require review against each supported macOS release.
Signing keys must remain outside the repository. Public binary releases must
pass the Developer ID, Hardened Runtime, notarization and Gatekeeper checks.
Never ship a developer keychain or tell users to disable Gatekeeper/TCC.

Before publishing, enable GitHub private vulnerability reporting and add the
repository's private reporting link here. Report security findings privately;
do not include credentials, captured audio, personal files or account responses
in a public issue. A maintainer response policy and supported versions must be
set by the publisher before public launch.
