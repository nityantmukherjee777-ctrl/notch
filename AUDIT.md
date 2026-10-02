# Release review — 29 September 2026

Scope: the current Swift/AppKit source, local process boundaries, network/media
input, signing/packaging scripts, permission lifecycle, and targeted runtime
checks on the development Mac. This is a focused source review and regression
pass, not a penetration-test certification or a guarantee of no vulnerabilities.

## Findings addressed

| Finding | Impact | Change |
| --- | --- | --- |
| Changing ad-hoc signing identity | macOS permission grants invalidated by updates | Persistent local certificate; fail if stable signing is unavailable; staged bundle replacement |
| Unbounded downloaded artwork/lyrics | Excessive memory use from remote responses or images | Streaming byte limits, exact HTTPS host and redirect policy, ephemeral sessions, image dimension limits and downsampling |
| Non-finite/huge media times, reset timestamps and saved values | Overflow, invalid scheduling or broken layout | Validate and clamp at input boundaries; regression fixtures |
| EOF callbacks on provider pipes | Repeated callbacks after a helper exits | Remove handlers on EOF; generation guards and reconnect logic |
| Fixed Codex installation paths | Usage stopped after Codex moved inside the ChatGPT bundle | Discover installed bundles and current/legacy CLI locations; preserve custom executable selection |
| Always-visible Codex satellite | Idle distraction and misleading activity | Compare reported quota consumption; 5-minute inactivity deadline; running-app check; keep quota accessible in toolbar |
| Percentage split across two text views | 100% could overflow a small bubble | One fitted monospaced percentage run; verified 0/9/99/100 layouts at 28 points |
| Lyrics back-arrow decoration accepted hits | Inconsistent pointer navigation | Decoration ignores hit testing; lyrics panel remains receptive to pointer clicks while open, and its presentation controller handles the arrow’s screen-space hit target directly |
| Activity list rebuilt all bubble windows | Appearance jumps and unrelated bubble resets | Stable per-activity panels; interruptible entrance/retraction; reduced-motion path |
| Whole-folder distribution risk | Accidental inclusion of unrelated personal documents or signing material | Curated source exporter and explicit public-binary gate |

## Verification

- Compatibility runner: **38 test bodies, zero failed assertions**. Covers timer
  restoration, independent activity layout, overflow, quota missing/auth/offline
  cases, disable/re-enable, malformed input, streaming response limits, executable
  discovery, and exact inactivity expiry. This runner is explicitly separate
  from the standard Swift Testing suite; see the toolchain limitation below.
- Generated-PCM visualizer harness passed: callback sizes, mono/stereo, sample
  rates, frequency localization, dynamics, silence/finite output, and persisted
  failure/explicit-retry behavior. It does not prove physical audio permission.
- Release app built, signed with the retained identity, and deep/strict verified.
  The designated requirement is stable; Hardened Runtime is enabled.
- Running build: live Codex quota read succeeded; artwork opened lyrics; back
  responded to an accessibility button press; the user confirmed a normal
  pointer click returned to the player in the corrected build. Settings reported Keyboard HUD ready after relaunch
  without another Accessibility prompt. The quota page was visually inspected.
- Percentage renderer checked 0%, 9%, 99%, and 100% in the 28-point circular
  layout. This was fixture rendering, not a fabricated live quota reading.
- Timeout behavior was checked with deterministic dates, not a claim that an
  uninterrupted 5-minute hardware session was observed.
- Public-binary gate correctly rejected the local candidate: Developer ID,
  secure timestamp, publisher bundle identifier, notarization and Gatekeeper
  approval are still absent.

## Remaining release gates

1. Publisher-owned identity, licence, support/security contact and GitHub
   destination. Public source availability does not itself grant an open-source
   licence. No repository or release has been published.
2. Developer ID signing and Apple notarization, including a clean downloaded
   installation and update on another Mac. Never ship the local private key.
3. Run the original Swift Testing suite using a matched toolchain/SDK.
4. Physical volume/brightness keys, audio capture across relaunch, sleep/wake,
   display attachment/removal, full-screen and rapid gesture/hover tests on the
   final notarized build. Accessibility status alone does not prove every key.
5. A controlled idle CPU run below the 1% target. Current 30/45-second samples
   were about 3.13%/2.53% for the app, with low helper CPU, but included activity;
   a stack sample showed UI actions and music queries. They do not establish an
   idle pass. Repeat with no interaction and investigate if the target is missed.
6. Review supported OS versions and third-party terms for the private
   MediaRemote/DisplayServices integrations and lyric/artwork services.

Codex activity now also observes local session-file modification events without
reading session contents. A live probe on this Mac detected these events; the
fixture test verifies delivery within two seconds, deduplication, stale-file and
symlink rejection, and stopping observation when disabled. This desktop build
has no shared app-server control socket, so direct runtime events are unavailable
here. Session writes are an activity approximation (including bookkeeping), not
an exact token counter; numeric quota continues to use the official app-server.

The cell-division entrance was inspected at six rendered intermediate frames.
Its temporary window ignores input, cleans up on interruption/completion, and
uses the existing display-link clock. Reduce Motion skips the transition.

See PRODUCTION.md for the distribution checklist, PRIVACY.md for current data
flows, SECURITY.md for reporting setup, and BACKLOG.md for future features.
