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
- [x] **A1. Double-tap side zones to skip ±10 s (touch layouts).** DONE
  (Q1=A, touch only). `_skipZones()` wraps `_video()` in `_portrait()` and
  `_landscape()`; a `LayoutBuilder`+`onDoubleTapDown/onDoubleTap` splits the
  width into thirds, left/right → `_skip(∓10s)` (broadcasts) + `_flashSkip()`
  (a 650 ms `_skipFlashBadge` over the video), middle ignored. Desktop's own
  `GestureDetector` is UNCHANGED — single-tap stays instant (no lag), per Q1.
- [x] **A2. Seek-preview tooltip on slider hover (desktop).** DONE. Added
  `onHover` (normalized 0–1, null on exit; self-gating — touch never hovers)
  to `PTSlider` via its `MouseRegion`. `RoomControlBar` tracks `_hoverValue`
  and floats a `_previewChip` through a `CompositedTransformFollower` in an
  unclipped outer `Stack` (the chip must escape `GlassPanel`'s ClipRRect,
  anchored to the slider by a `LayerLink`). Hidden while dragging / duration 0.
- [x] **A3. Buffering indicator.** DONE. `_buffering` subscribes to
  `widget.player.stream.buffering` (local) and reads `state == .buffering` in
  `_onYouTubePlayerEvent` (YT); reset on both mode switches. `_showBuffering`
  gates on intent (`_ytIntendedPlaying` for YT, `_playing` for local) so a
  paused buffer shows nothing. Centered spinner + dark scrim in `_video()`.
- [x] **A4. Fullscreen toggle (F, desktop).** DONE (Q2=B, OS window). Added
  `window_manager: 0.5.2` (exact pin), `windowManager.ensureInitialized()` on
  desktop in `main.dart`, new `lib/platform.dart` (`isDesktop`). `_RoomScreenState`
  is a `WindowListener`; F → `_toggleFullscreen()`, Esc order text→chat→
  `_exitFullscreen()`. `onWindowEnter/LeaveFullScreen` keep `_fullscreen` synced.
  NOTE: double-click binding intentionally OMITTED — it would reintroduce the
  ~300 ms desktop single-tap lag Q1 rejected. F + Esc only.

### B — Social awareness
- [x] **B1. Remote-action attribution toast.** DONE (Q3=B, seeks+play/pause).
  Rather than thread `senderId` through the routing callbacks (state_response
  reuses them — would toast on late-join), added a dedicated
  `Stream<RemoteAction> remoteActions` emitted ONLY from `_handlePlay/Pause/
  Seek` (never state_response/position_sync). `_onRemoteAction` resolves the
  name via `_present`/`_members` and shows a 3 s fading `GlassPill`
  ("«name» jumped to 12:40" / "hit play" / "paused") top-center of `_video()`.
- [x] **B2. Ephemeral chat overlay when the panel is closed.** DONE (Q4=B,
  last 3). `sync.chatMessages` listener calls `_pushOverlayChat` when
  `!_chatOpen`; `_overlayChat` holds ≤3, each self-expiring after 5 s (timers
  tracked, cancelled on open/dispose). `_chatOverlay()` renders bottom-left
  chat-bubble stack (fade+rise entry) in `_desktop()`+`_landscape()` only.

### C — Chat ergonomics
- [x] **C1. Auto-focus chat input when opening the panel (desktop only).**
  DONE. Added `autofocus` flag to `RoomChatPanel` (TextField `autofocus:`);
  passed `true` ONLY in `_desktop()`. Stays false for `embedded` (portrait)
  and the touch `_landscape()` overlay — no soft-keyboard pop. Esc/close
  focus handoff unchanged (`_toggleChat` → `_shortcutFocus`).
- [x] **C2. Eased enter/exit for the chat panel overlay.** DONE (user-requested,
  session 3). One `AnimationController` `_chatAnim` (250 ms, easeOutCubic in /
  easeInCubic out) drives both halves of the swap: `_chatRevealed()` slides the
  panel in from off the right edge (Stack clips the overshoot) and unmounts it
  at rest; `_chatDisplaced()` cross-fades what it covers (landscape facecam
  rail, floating bubbles). Desktop banner inset became `AnimatedPositioned` on
  the same curve. Panel is slid, NOT faded — an `Opacity` layer around
  `GlassPanel`'s `BackdropFilter` makes the blur sample an empty layer.

---

## 4. Open decisions to grill (resolve WITH the user before gated items)

> ALL RESOLVED 2026-07-25 (session 2). Answers below.

- **Q1.** Double-tap skip on which layouts? → **A) touch only** (portrait +
  landscape); desktop keeps instant single-tap controls toggle. — gated: A1 ✓
- **Q2.** Fullscreen meaning? → **B) OS window fullscreen** via new pinned
  package (`window_manager: 0.5.2`). — gated: A4 ✓
- **Q3.** Attribution toasts for which events? → **B) seeks + play/pause**
  (not drift/state_response). — gated: B1 ✓
- **Q4.** Ephemeral chat overlay shape? → **B) stack of last 3**, chat-bubble
  styling. — gated: B2 ✓

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

### R-C2. Chat panel transition
1. macOS, toggle chat repeatedly (button + Esc) → panel slides in/out smoothly,
   glass blur never flattens mid-slide, banners follow without a snap.
2. Toggle mid-animation → no flicker, no stuck half-open panel; caret lands in
   the input on every open (autofocus re-fires because the panel unmounts).
3. Chat closed with bubbles on screen → open: bubbles fade out under the panel,
   then clear. Click through the closed panel's slot (video area) still works.
4. Android landscape: facecam rail cross-fades against the panel, not a pop.

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

### 2026-07-25 (session 2) — all seven items implemented
- Grilled Q1–Q4 up front; user chose A/B/B/B (recorded in §4). Then built all
  seven items in one session, order: C1 → A3 → A2 → B1 → B2 → A1 → A4.
- Confirmed in code before building: state_response (`sync_service.dart` ~L524)
  reuses `onRemoteSeek/Play/Pause`, so B1 could NOT toast from those callbacks
  without firing on late-join — drove the dedicated `remoteActions` stream
  design (emit only from `_handlePlay/Pause/Seek`). Drift uses the separate
  `onRemoteDriftCorrect` path → naturally excluded. `GlassPanel` clips its
  child (ClipRRect) → A2's hover chip needed a `CompositedTransformFollower`
  in an outer unclipped `Stack`, not a plain `Positioned`.
- Files touched: `lib/rooms/room_screen.dart` (most items), `room_control_bar.dart`
  (A2), `room_chat_panel.dart` (C1), `lib/ui/inputs.dart` (A2 onHover),
  `lib/sync/sync_service.dart` (B1 RemoteAction+stream), `lib/main.dart` +
  new `lib/platform.dart` + `pubspec.yaml` (A4 window_manager 0.5.2).
- JUDGMENT CALL (A4): omitted the double-click→fullscreen binding. Q1 had the
  user explicitly keep desktop single-tap instant; onDoubleTap on that same
  detector reintroduces the ~300 ms lag. F + Esc cover fullscreen instead.
  Revisit if the user wants double-click after all (would accept the lag).
- Test status: `fvm flutter analyze` CLEAN (whole project). `fvm flutter pub
  get` resolved window_manager 0.5.2 (macOS target 10.15 ≥ its 10.11 req).
  NO device runs yet — the §6 recipes (R-A1..R-C1) are ALL still pending.
- DEVICE-VERIFY PENDING (do these before the PR):
  · A4 is the riskiest: window_manager fullscreen was NOT run on macOS. Basic
    `setFullScreen` should need no native subclassing, but VERIFY the F-toggle,
    Esc-exit ordering (open chat + type, then Esc twice), and the green-button/
    native-fullscreen path keeps `_fullscreen` synced via WindowListener.
    Windows/Linux desktop registration is a build concern — confirm those build.
  · A2 chip x-alignment uses `_sliderLink.leaderSize?.width` — eyeball that the
    chip sits under the cursor across the track width (R-A2).
  · A1 landscape single-tap now has the accepted ~300 ms lag — confirm it still
    feels OK (R-A1 step 3). A3 buffering needs network throttling (R-A3).
  · B1/B2 need two devices in a room (R-B1/R-B2): late-join must NOT toast;
    opening chat must clear the overlay with no duplicate.
- NEXT: run the §6 device recipes (start with A4 on macOS — highest risk). If
  all pass, per §1.9 migrate any durable notes into README/CLAUDE.md, then
  `git rm docs/room-ux-followups.md` BEFORE opening the branch PR. If A4
  fails on a desktop target, that's the one item to fix or gate behind a flag.

### 2026-07-25 (session 3) — C2 chat panel transition
- User asked for eased enter/exit on the chat overlay. Added C2 (see §3):
  one controller for the panel slide + the cross-fade of what it covers, so
  both halves of the swap can't desync.
- Two traps found while building, both encoded in the code comments:
  1. `Opacity` around `GlassPanel` kills the `BackdropFilter` (blurs an empty
     layer) → the panel slides only; only the non-glass chrome fades.
  2. The panel's `Positioned` hands down TIGHT constraints, so the collapsed
     `SizedBox.shrink()` still fills its slot and would eat clicks meant for
     the video → the zero state is wrapped in `IgnorePointer`.
- Opening chat no longer clears `_overlayChat` immediately (`_clearOverlayChat`
  → `_cancelOverlayChatTimers`); bubbles fade under the panel and are cleared
  by a status listener when the open animation completes. R-B2 step "opening
  chat clears overlay" is now "clears AFTER the 250 ms transition".
- Test status: `fvm flutter analyze` CLEAN (whole lib). NO device run — R-C2
  (and everything from session 2) still pending.
- NEXT: unchanged from session 2 — device recipes, R-C2 folded in.
