# Room Screen UX Follow-ups — LIVING DOC

> **Read §0–§3 before touching any code.** Single source of truth for the
> room-ux-followups initiative. Code is the source of truth; this doc is
> hypotheses.
>
> Any instance (Claude or human) picking this up:
> 1. Read §0 (mission), §1 (working agreement), §3 (audit board), and the LAST §8 entry.
> 2. Pick the first unchecked §3 item NOT gated on an unanswered §4 decision.
> 3. Grill the user (A/B/C options) before building.
> 4. Update §3 + append a §8 entry as the LAST step of every session.
> 5. At ~50–60% context usage, STOP and write a §8 handoff (template at top of §8).

---

## 0. Mission & non-goals

**Mission.** Finish the room screen's content-viewing UX polish. The first
pass (commit `3d13aab`, 2026-07-25) shipped: chat-input keyboard precedence,
full-width topbar, 3-second auto-hiding controls, seek-on-release scrubbing,
audio-track selection in the compact bar, and mute toggle (M key + volume
icon). This initiative implements the seven follow-up improvements identified
during that pass (§3). "Done" = all seven behave correctly on macOS desktop,
Android portrait, and Android landscape, verified with the §6 recipes.

**You are responsible for the success of this initiative.** Beyond the listed
items, audit your own area and take initiative to harden edge cases. Update
§3 when you discover new work.

### Non-goals (DO NOT do these)
- Do NOT touch the sync/echo-prevention layer's core mechanisms (`self: false`,
  `_isApplyingRemoteAction`, `_shouldApply`) — CLAUDE.md marks them fragile.
- No new playback features (playlists, speed control, PiP) — polish only.
- No redesign of the visual language — everything comes from `lib/ui/pt_theme.dart`.
- No YouTube-iframe surgery — its command latency quirks are handled; work
  around them, don't rewrite them.

---

## 1. Working agreement

The rules from `/living-doc`. Do not loosen them.

1. Code is the single source of truth. Verify every claim against the tree before acting.
2. One in-progress §3 item at a time. Finish or hand off first.
3. Append-only §8. Never rewrite past entries.
4. At ~50–60% context usage, STOP and write a §8 handoff.
5. Update §3 + §8 as the LAST step of every session.
6. Dates are absolute (YYYY-MM-DD).
7. Grill before building — A/B/C options. Park unresolved calls in §4.
8. Project rules: prefix all Flutter/Dart commands with `fvm`. There is no
   `test/` dir — verify with `fvm flutter analyze` + §6 manual recipes.
   pubspec.yaml versions are exact pins (no `^`). Dart dot-shorthand style
   (`_mode = .local`). Dark mode only; colors/typography via `PTColors`/`PTText`,
   never hardcoded hex in screens. Friendly error copy, never raw codes.
   No `Co-Authored-By` trailers in commits.
9. The closing instance deletes this doc (`git rm docs/room-ux-followups.md`)
   **before** opening the PR for this branch. Migrate any durable notes into
   README/CLAUDE.md first; the §8 history stays behind in git log.

---

## 2. Architecture as-it-is (code-grounded — verify before trusting)

> Verified against `main` @ `3d13aab` on 2026-07-25. Re-verify if the tree moved.

`RoomScreen` (`lib/rooms/room_screen.dart`) orchestrates everything: playback
mode (`_mode`: local media_kit / YouTube iframe), three layouts (`_desktop()`,
`_portrait()`, `_landscape()`), chat panel, facecam rail, banners, dialogs.
Desktop/landscape overlay the chrome on the video inside a `Stack`; portrait
puts controls in the column flow below a 16:9 `AspectRatio` video.

Mechanisms added by `3d13aab` that follow-ups build on:

- **Keyboard**: `_handleKeyEvent` on the body-level `Focus(_shortcutFocus)`.
  Ignores all shortcuts while an `EditableText` has focus (chat input); Esc
  refocuses `_shortcutFocus`, then closes chat. Handled keys call `_showControls()`.
- **Controls auto-hide**: `_controlsVisible` + `_controlsHideTimer` (3 s),
  `_showControls()` / `_scheduleControlsHide()` / `_toggleControlsVisible()`.
  `_overlayControls(child)` wraps topbar + control bar in
  `IgnorePointer`+`AnimatedOpacity`+`MouseRegion(opaque:false)`+`Listener`.
  Video tap toggles; desktop `MouseRegion.onHover` revives; never hides while
  paused or while `_pointerOverControls`.
- **Scrubbing**: `RoomControlBar` is stateful; `_dragValue` previews locally,
  `_endScrub` fires the single `onSeek` (which broadcasts) on release.
- **Sync events** (`lib/sync/sync_events.dart`): `PlayEvent`/`PauseEvent`/
  `SeekEvent` carry `senderId` + `timestamp` only — NO display name. Presence
  (`_present` in RoomScreen, `PresentMember`) maps user_id → display name.
  Remote actions reach RoomScreen via `sync.onRemotePlay/Pause/Seek/DriftCorrect`
  callbacks, which currently take no sender argument.

### Key files (verified paths)

| Concern | File |
|---------|------|
| Room orchestrator, layouts, keyboard, auto-hide | `lib/rooms/room_screen.dart` |
| Control bar (scrub state, buttons) | `lib/rooms/widgets/room_control_bar.dart` |
| Chat panel (TextField, bubbles, `embedded` flag) | `lib/rooms/widgets/room_chat_panel.dart` |
| PTSlider (custom painter, onChanged/onChangeEnd) | `lib/ui/inputs.dart` |
| Sync service + typed events | `lib/sync/sync_service.dart`, `lib/sync/sync_events.dart` |
| Theme, glass, banners, buttons | `lib/ui/pt_theme.dart`, `glass.dart`, `banners.dart`, `buttons.dart` |

---

## 3. Audit board (the work — tick as completed; ONE in-progress at a time)

> Legend: `[ ]` todo · `[~]` in progress · `[x]` done+verified ·
> `[?]` needs repro/logs · `[G]` blocked on a §4 decision.

### A — Playback interaction
- [G] **A1. Double-tap side zones to skip ±10 s (touch layouts).** Left/right
  thirds of the video surface skip -10/+10 s with a ripple/label flash.
  HAZARD: the video `GestureDetector` in `_desktop()`/`_landscape()` uses
  `onTap: _toggleControlsVisible`; adding `onDoubleTap` to the same detector
  delays single-tap recognition by the double-tap window (~300 ms), lagging
  the controls toggle. Decide per §4 Q1 whether desktop gets it at all.
  Portrait video (`AspectRatio` in `_portrait()`) currently has NO gesture
  detector — add one there for touch. Route through `_skip()` so it broadcasts.
- [ ] **A2. Seek-preview tooltip on slider hover (desktop).** Hovering
  `PTSlider` in the control bar shows the timestamp under the cursor before
  committing. Needs a hover callback on `PTSlider` (`lib/ui/inputs.dart` —
  it has a `MouseRegion` already but no onHover plumbing) surfacing the
  normalized x; `RoomControlBar` renders the label (glass chip above thumb).
- [ ] **A3. Buffering indicator.** No visual exists for a stalled player.
  Local: `widget.player.stream.buffering` (media_kit) — subscribe alongside
  the other streams in `_init()`. YouTube: `playerState == .buffering` in
  `_onYouTubePlayerEvent`. Show a centered spinner over the video (dark
  scrim, `PTColors.primary`), suppressed while paused.
- [G] **A4. Fullscreen toggle (F / double-click, desktop).** Scope per §4 Q2:
  in-app immersive (hide facecams/banners too) vs OS window fullscreen (needs
  a pinned package, e.g. `window_manager` — remember exact version pins).
  Wire F into `_handleKeyEvent`; keep Esc precedence order (text field →
  chat close → fullscreen exit).

### B — Social awareness
- [G] **B1. Remote-action attribution toast.** When a remote member
  seeks/pauses/plays, show "«name» jumped to 12:40" briefly so playback jumps
  don't read as glitches. Sender: extend `sync.onRemotePlay/Pause/Seek`
  callbacks to pass the event's `senderId` (already in every event payload —
  no protocol change), resolve name via `_present`. MUST ignore
  `position_sync` drift corrections and `state_response` application — only
  user-initiated events. Debounce per §4 Q3.
- [G] **B2. Ephemeral chat overlay when the panel is closed.** Float the
  latest message(s) near the bottom-left of the video for a few seconds
  (desktop/landscape; portrait chat is always visible — skip it). Data is
  already there: `sync.chatMessages` listener in `_init()` increments
  `_unread` when `!_chatOpen` — same branch triggers the overlay. Style/count
  per §4 Q4.

### C — Chat ergonomics
- [ ] **C1. Auto-focus chat input when opening the panel (desktop only).**
  Focus clash is solved, so opening chat should focus the `TextField` in
  `RoomChatPanel`. Add an `autofocus`-style flag; MUST stay false for
  `embedded` (portrait) — autofocus there pops the soft keyboard on room
  entry. Verify Esc still hands focus back and closing chat refocuses
  `_shortcutFocus` (`_toggleChat`).

---

## 4. Open decisions to grill (resolve WITH the user before gated items)

- **Q1.** Double-tap skip on which layouts? — options: A) touch only
  (portrait+landscape), desktop keeps instant single-tap controls toggle
  (recommended) B) everywhere, accepting ~300 ms tap lag on desktop
  C) everywhere, desktop single-tap becomes play/pause like YouTube — gates: A1
- **Q2.** Fullscreen meaning? — options: A) in-app immersive (hide all chrome
  incl. facecams; no new dependency) B) OS window fullscreen via new pinned
  package C) both, F cycles — gates: A4
- **Q3.** Attribution toasts for which events? — options: A) seeks only
  (jumps are the confusing ones) B) seeks + play/pause C) all, capped at one
  toast per sender per ~5 s — gates: B1
- **Q4.** Ephemeral chat overlay shape? — options: A) single latest message,
  ~4 s fade B) stack of last 3, chat-bubble styling C) skip the feature
  (unread badge is enough) — gates: B2

---

## 5. (reserved)

---

## 6. Device/manual test recipes

> Run `fvm flutter run -d macos` for desktop; a physical Android phone for
> touch layouts. Two instances (macOS + phone) in one room exercise the sync
> paths. Baseline regressions to re-check after EVERY item: chat typing never
> triggers shortcuts; controls auto-hide at 3 s and revive on tap/hover/keys;
> scrub broadcasts once on release.

### R-A1. Double-tap skip
1. Phone, landscape, video playing, controls hidden.
2. Double-tap right third → +10 s, flash label, second device follows.
3. Single tap still toggles controls without noticeable lag.

### R-A2. Hover preview
1. macOS, hover mid-slider without clicking → timestamp chip at cursor x.
2. Move off → chip gone; click → seek lands where the chip said.

### R-A3. Buffering
1. macOS, YouTube mode, throttle network (Network Link Conditioner).
2. Spinner appears while stalled, disappears on resume; nothing while paused.

### R-A4. Fullscreen
1. macOS, press F → fullscreen; F/Esc exits. Esc order: typing-unfocus,
   then chat-close, then fullscreen-exit (open chat + type to verify).

### R-B1. Attribution toast
1. Two devices; seek on phone → macOS shows "«name» jumped to …".
2. Let host heartbeat drift-correct (>1.5 s drift) → NO toast.
3. Late-join a playing room → NO toast from state_response application.

### R-B2. Chat overlay
1. macOS, chat closed, send message from phone → overlay appears + fades;
   unread badge still increments; open chat → no duplicate.

### R-C1. Chat autofocus
1. macOS, open chat → caret in input, typing works immediately, space types
   a space. Esc → focus back to player (space now play/pauses). Reopen on
   phone portrait → soft keyboard does NOT auto-pop.

---

## 7. Robustness patterns to adopt

- **Remote vs local actor discipline.** Anything user-visible triggered by
  sync events must distinguish user-initiated events from mechanical ones
  (`position_sync`, `state_response`, echo settle). When adding callbacks,
  thread `senderId` through rather than guessing from state.
- **Focus is a resource.** Any new focusable surface must define who gets
  focus back when it closes (see `_toggleChat` → `_shortcutFocus.requestFocus()`).
  Esc handling is ordered; new Esc consumers must slot into that order explicitly.
- **Overlay chrome goes through `_overlayControls`.** New floating UI on the
  video either joins the auto-hide group or documents why it stays
  (banners/facecams stay; chrome hides).
- **Broadcast on gesture end, preview locally during.** Same pattern as
  `_dragValue` scrubbing — never broadcast per-tick.

---

## 8. Findings & handoff log (append-only — newest at BOTTOM)

> Every session: what was confirmed in code, what was changed, test/device
> status, and a `NEXT:` line. At ~50–60% context, STOP and write a handoff
> using the template.

### Handoff prompt template (copy, fill, paste for the next instance)
```
You are continuing the room screen UX follow-ups. Read
docs/room-ux-followups.md §0–§3 fully (code is the source of truth — verify
everything). Current branch: <branch>. Last completed: <item/§>. In progress:
<item> — <exact state, files touched, what's left>. Blocked-on grills:
<Q#s + status>. Test status: <analyze/manual recipes run>. Device-verify
pending: <list>.
NEXT: <the single next action>. Follow §1 working agreement.
```

### 2026-07-25 (session 1) — initialized
- Scaffolded living doc after shipping the first UX pass as `3d13aab`
  (keyboard precedence, topbar width fix, auto-hide controls, seek-on-release,
  compact audio-track button, mute toggle).
- What I confirmed in code: `PlayEvent`/`PauseEvent`/`SeekEvent` carry
  `senderId` but no display name (`lib/sync/sync_events.dart:26-73`) — B1
  needs the presence list for names, no protocol change. Portrait video has
  no gesture detector (`_portrait()` wraps `_video()` in a bare
  `AspectRatio`) — A1 adds one. `PTSlider` has a `MouseRegion` but no hover
  position plumbing (`lib/ui/inputs.dart`) — A2 extends it.
- §3 seeded with: A1–A4, B1–B2, C1 (the seven follow-ups from the first pass).
- §4 open: Q1 (double-tap layouts), Q2 (fullscreen scope), Q3 (toast events),
  Q4 (chat overlay shape). A2, A3, C1 are ungated.
- NEXT: grill the user on Q1–Q4, then start with an ungated item — C1 is the
  smallest (chat autofocus), A3 (buffering indicator) the highest-value.
