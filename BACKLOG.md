# Release roadmap

The September 13–14 request brought media polish, lyrics, browser Now Playing, gestures and HUDs forward. Version numbers below are planned milestones, not delivery dates. Implement and verify each feature separately. Camera mirror remains excluded.

| Version | Scope | Status |
| --- | --- | --- |
| 1.0 | Native notch, desktop music, timer, Keep Awake, battery, volume, Codex and settings | Local first release |
| 1.1 | Uniform reference-shaped pages, icon toolbar, fixed-canvas animation, reliable pointer dwell, artwork and back navigation in lyrics, hide paused media, supported browser/app Now Playing, widget/source swipes, exclusive keyboard volume/brightness HUD | Current review build |
| 1.2 | File shelf: drag files in, inspect/open/remove items, safe temporary storage | Planned next |
| 1.3 | Opt-in clipboard history and saved snippets; history stays memory-only until quit | Planned |
| 1.4 | Calendar and reminders, then meeting countdown and join | Planned |

After those milestones, retain these as individual reviewed steps:

1. Browser extension for independent Chrome/Brave tabs and standard web media not exposed through Now Playing.
2. Claude subscription quota: independent provider, switch and bubble; validate Code and desktop/Cowork data access and freshness, separate from context tokens.
3. Agent working/attention/completion and broader device connection alerts. Bluetooth connection animation is included in build 12, with reported connected-device battery in build 15. Non-Bluetooth alerts and broader device-model artwork remain planned.
4. Screenshot capture, then separately screen recording with optional audio and a persistent stop control.
5. Download completion, safe drive eject, and screenshot OCR separately.
6. Teleprompter: script, text size, scroll speed, pause/resume and keyboard controls.
7. Quick notes, app/Shortcuts launcher, system stats, weather, world clocks and customization individually.
8. **Wispr Flow-style dictation:** hold-to-talk and toggle recording, transcription, punctuation and filler cleanup, optional rewriting/tone, vocabulary, and insertion into the active text field with a preview/undo path. Separate raw dictation from rewriting so meaning is preserved. Show an unmistakable local recording indicator and stop/cancel controls. Choose local versus cloud speech/model processing, supported languages, latency targets, offline behavior and cost at this milestone. Microphone permission is requested only when enabled; no audio retention by default. This expands the previously planned Lemon-like voice tools; it is a new Notch implementation, not a copy of proprietary code or branding.
9. **Live meeting/interview assistant (Cluely-inspired):** user-started microphone/system-audio transcription, question detection, concise suggested answers, follow-ups, and notes in the notch. Ground answers in the user's supplied résumé, examples and documents, label uncertainty, and let the user review/edit; do not fabricate experience. Include visible local listening/stop controls, participant-consent guidance, and opt-in transcript saving/deletion. Add a presentation-privacy mode that excludes the assistant surface from screen sharing where supported; verify each target conferencing app/capture mode and clearly disclose unsupported modes. Do not promise universal invisibility. Choose the model/provider and data handling separately from dictation. Mock-interview practice and feedback can follow the live workflow. Implement and validate this as its own milestone after dictation.

The September 22 request explicitly adds live interview assistance and presentation privacy to the plan. These remain future features; neither microphone dictation nor meeting assistance is included in v1. Their final version numbers follow the earlier independently reviewed milestones rather than a fixed delivery date.

Later candidate: Coding / Presenting / Personal workspace presets that change tools and launch selected apps/files, informed by [LaunchMe’s workspace and notch integration](https://launchmeapp.com/blog/launchme-update-2-0-notch.html).
