# PlayTogether Animation & Motion Plan

Working scratchpad for adding macro + micro animations across the app. Written after a
full pass over `lib/` (Feb war-room: login, lobby, profile, room, dialogs, control bar,
chat, readiness overlay, facecams, shared UI kit). Treat this as the design brief +
implementation backlog; tick items off as they land.

---

## 1. Motion philosophy for this app

PlayTogether is a **dark, violet-glass "living room"**: people settle in to watch
something together. Motion should feel like the room itself — calm, weighted, a little
luxurious — never like a productivity app. Concretely:

- **Glass glides, it doesn't pop.** Surfaces slide/scale on curved easing; nothing
  teleports in or out. (The chat panel already does this perfectly — it's the reference.)
- **Motion carries meaning first, delight second.** Every animation should answer one of:
  *where did this come from / go?* (continuity), *what just changed?* (state),
  *who did that?* (social attribution), or *is the app alive?* (ambient).
- **The video is sacred.** Nothing animates over or near the playing video except things
  the user or a peer explicitly caused (toasts, skip badges, chrome). No ambient motion
  inside the room while media plays.
- **Sync events stay honest.** Attribution toasts / gate feedback remain user-initiated
  only (existing invariant). Motion must never make a mechanical correction look like a
  human action, and never delay a broadcast (animate the *presentation*, never the
  *event*).
- **Fast is a feature.** The desktop single-tap-to-toggle-chrome decision (no double-tap
  lag) is a product call; nothing in this plan may add latency to input handling.

### Timing & easing scale (the whole app uses only these)

| Token | Duration | Curve | Use |
|---|---|---|---|
| `PTMotion.tap` | 90 ms | `easeOutCubic` | press feedback (scale/opacity) |
| `PTMotion.hover` | 140 ms | `easeOutCubic` | hover fills, chips, small fades (≈ today's `Durations.short2`) |
| `PTMotion.state` | 220 ms | `easeOutCubic` / `easeInCubic` out | state swaps: icons, badges, banners |
| `PTMotion.panel` | 300 ms — **shipped 250** | `Curves.easeOutCubic` in / `easeInCubic` out | panels, overlays, dialogs (= today's `_chatMotion`; see §9.6) |
| `PTMotion.page` | 350 ms — **shipped 280** | `easeOutCubic` in / `easeInCubic` out (see §9.6) | route transitions |
| `PTMotion.ambient` | 6–14 s | `easeInOutSine`, looped | glow drift, breathing (login/lobby only) |

One overshoot curve for "arrival" moments only (`Curves.easeOutBack` at low magnitude,
scale 0.95→1.0): unread badge pop, "Everyone's ready" toast, code-input completion.
Never use bounce/elastic anywhere else — it fights the glass aesthetic.

---

## 2. Foundation work (do this first)

### 2.1 `lib/ui/pt_motion.dart` — motion tokens
New file next to `pt_theme.dart`:

- `PTMotion` abstract final class with the durations/curves above (mirrors `PTColors`
  / `PTText` so screens never hardcode `Duration(milliseconds: …)` again).
- `bool reducedMotion(BuildContext c) => MediaQuery.disableAnimationsOf(c);`
  Every *decorative* animation (ambient drift, entrance staggers, shimmer) must check it
  and render the end state instead. *Functional* motion (panel slides, dialog fades) can
  stay but should drop to ~half duration.

### 2.2 Small reusable primitives (also in `lib/ui/`)

- **`PTEntrance`** — fade (0→1) + translate (12 px up→0) + optional scale (0.98→1) on
  mount, with a `delay` parameter for staggering. One `TweenAnimationBuilder`-style
  widget; used by lobby cards, dialog content rows, readiness roster rows.
- **`PTPressable`** — wraps a child with scale-on-press (1.0→0.97, `PTMotion.tap`) +
  the existing MouseRegion hover pattern. Retrofit into `PTButton`, `PTIconButton`,
  `PTPlayButton`, `GlassPill(onTap:)`, chat send button — today they all have hover
  states but **zero press feedback**, which is the single biggest "feels static" gap on
  touch.
- ~~**`PTAnimatedVisibility`**~~ — built, then dropped as unused; see §9.7. Shipped
  instead: **`PTShake`** (join-code "nope") and **`PTPulse`** (looping opacity breath,
  used by the countdown icon under 1:00 and the ended-room dialog glow).

### 2.3 Route transitions (macro) — `app_router.dart`

Today every route uses the default `MaterialPage` (platform zoom/cupertino push). Replace
with `CustomTransitionPage` per route, **preserving the nested lobby→room stack** (the
push/pop direction semantics are load-bearing — see the router comment):

- **login ⇄ lobby** — *fade-through*: outgoing fades to 96 % scale, incoming fades in at
  102 %→100 %. Feels like a scene change, not navigation — appropriate because auth swaps
  the whole world.
- **lobby → room** (push) — the room *rises*: incoming slides up 24 px + fades over
  `PTMotion.page`; on pop it sinks back down. Sells "entering the theater" and reads
  correctly in reverse for every `go('/lobby')` exit (leave, eviction, end-room).
- **lobby → profile** (push) — subtle shared-axis horizontal (incoming +16 px from the
  right, outgoing –8 px) since it's a sibling detail page.
- Keep transitions **under 400 ms** and fade-dominant: the room screen mounts a video
  surface + possibly a WebView; heavy transform animations over platform views jank.
  (Test the YouTube-mode re-entry path on macOS specifically.)

---

## 3. Macro animations by screen

### 3.1 Login (`login_screen.dart`)
- **Entrance choreography** (once, on first build): brand logo `PTEntrance` (scale
  0.9→1 + fade, 400 ms), then wordmark/tagline (+60 ms), then the glass card / action
  column (+120 ms), then terms note (+180 ms). Skipped under reduced motion.
- **Ambient**: the brand logo's violet `BoxShadow` breathes — blur radius 32→40 and
  alpha 0.45→0.55 over ~5 s loop. Cheap (one repaint boundary around the logo), and it
  makes the idle screen feel alive. Also applies to the lobby `_Wordmark`? **No** — one
  breathing element per screen, and the lobby's is the greeting (below).
- **Sign-in handoff**: when a sign-in succeeds the router redirect swaps screens; the
  fade-through route transition (§2.3) covers this — no extra work.

### 3.2 Lobby (`lobby_screen.dart`)
- **Card entrance stagger**: greeting → subtitle → create card → join card, 60 ms apart,
  each `PTEntrance`. Only on entry from login/cold start (guard with a static "played
  this session" flag) — returning from a room should be instant familiarity, not a
  re-performance.
- **Greeting**: keep the existing `AnimatedSwitcher`; lengthen to `PTMotion.state` and
  add a 4 px vertical slide between the placeholder "there" → real name swap.
- **Duration slider label** (`_durationLabel`): wrap in `AnimatedSwitcher` (fade+slide
  4 px, `PTMotion.hover`) keyed by the label text so "2h 30m" ticks pleasantly while
  dragging. Cheap, high-touch — the user stares straight at it while choosing.
- **Join-code error shake**: when `_join` fails / wrong length, horizontally shake the
  `PTCodeInput` (±6 px, 3 oscillations, 300 ms) alongside the existing snackbar + clear.
  Universal "nope" affordance.
- **Code completion**: on the 6th character, pulse each filled box border violet once
  (staggered 25 ms left→right) — a tiny "ready to go" flourish before Join is pressed.
- **Create/Join buttons**: `PTPressable` press scale + the loading swap becomes an
  `AnimatedSwitcher` (label ⇄ spinner cross-fade) instead of an instant swap.

### 3.3 Profile (`profile_screen.dart`)
- Route transition from §2.3 does the heavy lifting.
- **Avatar upload**: while `_uploadingAvatar`, overlay the avatar with a dim + spinner
  that *fades in* (`PTAnimatedVisibility`); on success, scale-pulse the new avatar
  (1.0→1.06→1.0, `PTMotion.state`) — confirmation without a snackbar.
- **Display-name save**: the profile row text swaps via `AnimatedSwitcher` when
  `ProfileService` notifies (same pattern as the lobby greeting).

### 3.4 Room (`room_screen.dart`) — macro moments

- **Entry**: the route slide-up (§2.3) + the existing "Setting up the room…" spinner.
  Upgrade the spinner state: cross-fade between the loading scaffold and the real layout
  (`AnimatedSwitcher` at the `build()` top level, `PTMotion.panel`) so the room *resolves*
  instead of flashing in.
- **Readiness overlay (`ReadinessOverlay`)** — currently mounts/unmounts with **no
  animation** (`if (_gateState == closed)` in the video stack). This is the app's most
  dramatic state change and deserves its most careful motion:
  - In: scrim fades in (180 ms) while the glass card does fade + scale 0.96→1
    (`PTMotion.panel`). Out: reverse, slightly faster (200 ms) — the *reveal of the
    video* is the payoff, don't make people wait for it.
  - Wrap via `AnimatedSwitcher` around the overlay slot (child keyed by gate state).
    The scrim is a plain `Container` color — safe to fade; the `GlassPanel` inside is
    **not** faded independently (§7), it rides the scale/scrim.
  - Roster rows (`_MemberStatusRow`): `PTEntrance` stagger (40 ms) on first open;
    status chips swap via `AnimatedSwitcher` (fade+slide) when Loading→Ready etc., and
    the chip's tint `AnimatedContainer`s between colors. Watching your friends' chips
    flip green one by one is the "we're all here" moment — make it legible.
  - When the gate opens and playback auto-resumes, the existing "Everyone's ready —
    resuming" toast gets the arrival overshoot (§1).
- **"That's a wrap!" / kicked dialog**: already goes through `showGlassDialog` (fade +
  scale + barrier blur — good). Add a slow rotation-free *glow pulse* behind the
  moon/person icon circle (opacity 0.18→0.28 loop) so the terminal dialog feels
  intentional, not abrupt.
- **Fullscreen toggle (desktop)**: OS-animated; nothing to do. Just make sure the
  chrome fade (below) doesn't fight the native transition — current code is fine.

---

## 4. Micro animations — room internals

### 4.1 Control bar (`room_control_bar.dart`, `buttons.dart`, `inputs.dart`)
- **Play/pause morph**: `PTPlayButton` swaps `Icons.play_arrow_rounded` ⇄
  `pause_rounded` instantly. Replace with `AnimatedIcon(AnimatedIcons.play_pause)`
  driven by a small controller (`PTMotion.state`) — the canonical video-player micro.
  Add press scale via `PTPressable`.
- **Skip buttons**: on press, spin the `replay_10`/`forward_10` glyph −/+ 40° and back
  (`PTMotion.state`) — mirrors the flash badge and confirms direction.
- **Slider (`PTSlider`)**: the painter already draws a glowing thumb. Animate:
  - thumb radius +2 px on hover/drag (pass a `t` into the painter from an
    `AnimatedContainer`-style tween in the widget),
  - the hover **preview chip** currently pops — fade+rise it in/out
    (`PTAnimatedVisibility`, 120 ms).
  - Scrub behavior stays exactly as-is (**preview locally, broadcast on release** —
    invariant).
- **Volume icon**: cross-fade `volume_up ⇄ volume_off` via `AnimatedSwitcher`
  (`PTMotion.hover`).
- **Transport hint line**: appears/disappears with `AnimatedSize` + fade so the bar
  doesn't jump a row height when the gate closes.
- **Disabled state**: `AnimatedOpacity` already covers dimming; add 150 ms `AnimatedAlign`
  nothing else — do *not* animate the enable/disable of individual buttons separately,
  it reads as flicker when the gate flaps.

### 4.2 Chrome & overlays
- **Controls auto-hide**: currently `AnimatedOpacity` only. Add a small drift — top bar
  translates −8 px as it fades, bottom bar +8 px (`PTMotion.state`) — so the chrome
  *retreats* rather than dissolves. Keep the existing `IgnorePointer`/MouseRegion logic
  untouched (it's subtle and correct).
- **Action toast** ("«name» jumped to 12:40"): today fade-only. Give it fade + drop-in
  from −10 px on show, fade + rise on hide; when the *text changes while visible*,
  cross-fade the label via `AnimatedSwitcher` instead of hard-swapping. It's kept
  mounted while faded (deliberate — preserve that).
- **Skip flash badge**: keep the fade-out, add scale 0.85→1.0 on appear (overshoot-free)
  so the ±10 s stamp feels physical.
- **Floating chat bubbles**: entrance already animates (fade+rise). Add the missing
  **exit**: instead of `_overlayChat.remove(message)` popping the widget, mark the
  message "expiring" and fade+slide it out (250 ms) before removal, staggering the
  `Column` reflow with `AnimatedSize`. Keep the "clear instantly under the arriving
  panel" path (`_chatAnim` status listener) as an immediate removal — the panel covers
  it anyway.
- **Banners (`_banners()` / `PTBanner`)**: mounts pop in today. Route the list through
  an animated container: each banner fades + slides down 8 px on entry and collapses
  (`AnimatedSize`) on dismiss. The T-5 warning additionally does one attention pulse on
  arrival (scale 1.0→1.02→1.0). Keep the stable `ValueKey`s — they're what stops the
  countdown ring restarting every tick.
- **Reconnecting banner**: the `sync_rounded` icon should rotate slowly while
  disconnected (linear, 1.2 s/turn) — the universal "working on it" cue, and it makes
  the banner feel live rather than stuck.
- **Room pill countdown**: when `_timeLeft` crosses 5:00, tick the mono label color
  from `white(0.7)` → `PTColors.warning` via `AnimatedDefaultTextStyle`; under 1:00 add a
  gentle 1 Hz opacity pulse on the schedule icon. No layout movement — it sits next to
  the video.
- **Copy code/invite**: on tap, morph the `content_copy` glyph to a `check` for 1.2 s
  (`AnimatedSwitcher`) inside `RoomCodeChip` — instant feedback where the eye already
  is; snackbar stays for the invite link path.

### 4.3 Chat (`room_chat_panel.dart`, `identity.dart`)
- **Panel slide**: already excellent (and documents the glass/Opacity trap). Leave the
  mechanism; just retarget durations to `PTMotion.panel` tokens.
- **New message entrance**: bubbles appear with fade + 6 px rise + slight horizontal
  origin bias (own messages from the right, others from the left), `PTMotion.state`.
  Implement in `itemBuilder` with a one-shot `PTEntrance` keyed by message identity —
  only animate messages appended *after* mount (history load and reconnect-merge must
  render statically; diff against `_seenCount`-style bookkeeping that already exists).
- **Typing row**: `TypingDots` already animates; mount/unmount the row with
  `AnimatedSize` + fade so the list extent doesn't jump.
- **Unread badge (`UnreadBadge`)**: pop in with the arrival overshoot; on increment,
  scale-pulse (1.0→1.15→1.0, 150 ms). The count text cross-fades via `AnimatedSwitcher`.
- **Send button**: `PTPressable`; on send, a quick 1.0→0.92→1.0 dip — tactile "sent".

### 4.4 Presence & facecams (`facecam_rail.dart`, overflow menu)
- **Facecam tiles**: mount/unmount with fade + scale 0.95→1 (`PTMotion.state`) as
  members join/leave or toggle cams — people appearing in the room is a social event,
  give it a beat. Rail reflows via `AnimatedSize`.
- **Speaking indicator**: replace the static `graphic_eq` icon flash with an animated
  treatment: while `isSpeaking`, the tile border glows violet (animate border color +
  shadow alpha, 200 ms in / 600 ms out so it lingers like voice does). This is the
  highest-value AV micro — it's how you know who laughed.
- **Mic-off badge**: fade+scale in/out instead of popping.
- **Presence dot (`PTAvatar.presence`)**: when a member comes online, one soft ripple
  ring expanding from the dot (600 ms, then never again until the state changes). No
  continuous pulsing — 8 avatars pulsing forever is noise.
- **Overflow menu**: entrance is fine (fade + 2 % slide). Add: member rows animate
  online⇄away via the existing `Opacity` becoming `AnimatedOpacity`
  (`PTMotion.state`); readiness chips same treatment as the overlay's; hover fill on
  `_ActionRow` becomes `AnimatedContainer` (140 ms) instead of instant.

### 4.5 Dialogs (`glass.dart`, player dialogs)
- `showGlassDialog` transition is already good (fade + 0.96 scale + animated barrier
  blur). Two upgrades:
  - **Content stagger**: dialog children (`ModeSelectionDialog` options, kick dialog
    buttons) get `PTEntrance` with 40 ms steps after the shell lands — glass arrives,
    then its contents settle.
  - **Exit**: `showGeneralDialog`'s reverse already plays the transition backwards; no
    change needed, but verify the barrier blur ramps *down* on pop (it does — it's
    driven by `animation.value`).
- **Mode selection cards**: hover lift (translate −2 px + border brighten,
  `AnimatedContainer`) + press scale. These are the "what are we watching?" moment —
  they should feel like physical cards.

---

## 5. Ambient layer (idle screens only)

`AmbientBackground` (login/lobby/profile) renders three static `_GlowBlob`s. Make them
**drift**: each blob slowly translates along its own elliptical path (± 30–50 px) and
scales ± 4 %, periods 9/12/15 s so they never sync. Implementation: one
`AnimationController` in `AmbientBackground` (converted to Stateful), three phase-offset
sine transforms; wrap each blob in `RepaintBoundary`.

- **Never in the room screen** — `AmbientBackground` isn't used there anyway; keep it so.
- Hard-gated behind `reducedMotion` and paused when the route isn't current
  (`TickerMode` handles this for free if driven by a ticker in the subtree).
- Measure first on the weakest target (Android): three large blurred circles
  repainting continuously can be surprisingly cheap (they're `ImageFiltered` leaves)
  but verify with the repaint rainbow before shipping; a 20 s period + `Transform`
  (layer-only) keeps raster work minimal.

---

## 6. Implementation phases

**Status: all four phases implemented.** Deviations from the brief as written,
and why, are recorded in §9. Outstanding verification is listed in §8.

Ordered by delight-per-effort; each phase ships independently.

**Phase 1 — Foundation + biggest wins**
1. `pt_motion.dart` tokens + `PTPressable` + `PTEntrance` + `PTAnimatedVisibility`.
2. Press feedback on all buttons (retrofit `PTButton`/`PTIconButton`/`PTPlayButton`/
   `GlassPill`/send button).
3. Route transitions (login fade-through, room rise, profile shared-axis).
4. Readiness overlay in/out + chip transitions.
5. Play/pause `AnimatedIcon` morph.

**Phase 2 — Room chrome polish**
6. Banner mount/dismiss motion + reconnecting spinner + T-5 pulse.
7. Action toast drop-in + cross-fade; skip badge scale; chrome retreat drift.
8. Chat message entrance, unread badge pop, typing-row `AnimatedSize`, bubble exit fade.
9. Copy-code check morph; transport hint `AnimatedSize`; volume icon cross-fade.

**Phase 3 — Social & AV**
10. Facecam tile mount/speaking glow/mic badge.
11. Presence ripple; overflow-menu row/chip transitions.
12. Room entry cross-fade (loading → layout).

**Phase 4 — Lobby/login delight + ambient**
13. Login entrance choreography + logo shadow breathing.
14. Lobby stagger, slider label ticker, code shake/completion pulse.
15. Ambient blob drift (perf-gated).
16. Profile avatar pulse + name swap.

---

## 7. Hard constraints & traps (encode into review checklist)

These come from the codebase's own war stories — violating them re-introduces fixed bugs:

1. **Never wrap `GlassPanel` (any `BackdropFilter`) in `Opacity`/`FadeTransition`** —
   the blur samples an empty layer and the glass goes flat. Animate glass by
   **slide/scale/clip**, or fade a *scrim behind it*. (Chat panel comment documents this.)
2. **Collapsed overlays in `Positioned` slots still eat clicks** — any new zero-state
   must keep the `IgnorePointer` pattern (`_chatRevealed` reference).
3. **`gateState == indeterminate` renders as usable** — the readiness overlay's new
   entrance animation must key off `closed` only; animating in on indeterminate would
   flash the overlay on every room entry.
4. **Attribution toasts stay user-initiated-only** — new motion on `remoteActions`
   consumers must not add feedback to `state_response` or drift-correct paths.
5. **Broadcast on gesture end, preview locally during** — slider/thumb animations are
   presentation-only; never move the broadcast earlier/later.
6. **No new `onDoubleTap` on the desktop video gesture detector** (300 ms single-tap lag
   — deliberate product call). Touch skip zones already exist; don't touch the ordering
   of Esc handlers or `_shortcutFocus` handback when animating chat/fullscreen.
7. **Don't animate over platform views casually** — the YouTube WebView and
   `media_kit` texture. Transforms *containing* them during route transitions must be
   fade-dominant; test macOS YouTube mode (the cursor-flicker known issue lives there —
   do not attempt drive-by fixes, see `docs/known-issues.md`).
8. **Keyed stability**: the T-5 banner's `ValueKey` (countdown restart bug) and the
   `ObjectKey(controller)` on `YoutubePlayer` must survive any wrapper widgets added
   for animation.
9. **Timers & controllers**: every new `AnimationController` needs disposal in the
   already-long `RoomScreen.dispose`; prefer self-contained widgets (own controllers)
   over adding more state to `_RoomScreenState`.
10. **Reduced motion**: decorative animation checks `MediaQuery.disableAnimations`;
    functional animation shortens. Applies to: entrance staggers, ambient drift,
    breathing glows, ripple, speaking linger.
11. **Style**: durations/curves come from `PTMotion` only (no inline
    `Duration(milliseconds:)` in screens); dot-shorthand enum style; exact-pin any new
    dependency — though this plan intentionally needs **no new packages** (everything is
    implicit-animation / `AnimationController` territory; `flutter_animate` was
    considered and rejected to keep the pin set small and the motion vocabulary
    hand-tuned).

## 8. Verification checklist (per phase)

- [x] `fvm flutter analyze` clean; `fvm flutter build macos --debug` succeeds.
- [ ] Everything below still needs a human at a running app.
- Two-instance sync smoke test (instance B via `./build/pt-instance-b.sh`): play/pause/
  seek/gate/chat all still sync; no animation delays a broadcast (watch for the
  100 ms settle window — nothing may defer `broadcast*` calls).
- Overlay layouts: chrome auto-hide + chat panel + bubbles interplay unbroken in
  desktop *and* landscape; portrait unaffected by overlay-only changes.
- Readiness overlay: enter room (no flash on indeterminate), host picks file, second
  client joins mid-play (gate closes/opens with motion), wrong-file chip transition.
- Perf: repaint-rainbow pass on lobby (ambient) and room (control bar, toasts) — no
  full-screen repaints introduced; ambient layer paused off-route.
- Reduced-motion (macOS: System Settings → Accessibility → Display → Reduce motion):
  staggers/ambient/breathing gone, app fully usable.

---

## 9. What actually shipped — deviations from the brief

Recorded here because each one was a deliberate correction, not an oversight.

1. **Readiness overlay is not wrapped in an `AnimatedSwitcher`.** §3.4 asked for
   one while §7.1 forbids fading glass — and `AnimatedSwitcher`'s default
   transition *is* a fade, over a slot whose root wraps the `GlassPanel`. Instead
   `ReadinessOverlay` takes a `reveal` 0→1 and tweens the panel's own
   `opacity`/`blur`/`borderColor` arguments plus scrim alpha and scale. That is a
   real fade with no opacity layer anywhere near the `BackdropFilter`. The slot
   stays mounted while `reveal > 0` so the exit plays and so the roster stagger
   fires when the overlay appears rather than when `RoomScreen` builds.
2. **`PTEntrance` has a `fade` flag, and lobby cards pass `fade: false`.** The
   §3.2 stagger targets `GlassPanel`s — same trap as above. Glass gets slide +
   scale; contents *inside* a panel sit above its filter and may fade freely.
3. **No `AnimatedIcons.play_pause`.** Those are Material's *sharp* glyphs and
   this app is rounded throughout; at 32 px inside the gradient button it reads
   as a foreign icon set. `PTPlayButton` cross-fades + scales the existing
   rounded glyphs instead.
4. **Chat entrance tracks a `Set` of already-animated message keys.**
   `itemBuilder` re-runs on every scroll-back, so the `_seenCount` approach in
   §4.3 would replay the animation indefinitely. Keys are value-based
   (sender|sentAt|content) so the reconnect history merge doesn't re-animate the
   backlog.
5. **Ambient drift is translation-only** — no `± 4 %` scale. A per-frame scale
   invalidates the raster cache on 640–720 px blurred circles and re-blurs every
   frame; a pure `Transform.translate` moves the cached layer.
6. **Timings trimmed.** `page` 350 → **280 ms** (room entry already waits on an
   async load; `easeInOutCubicEmphasized` is tuned for M3's 500 ms envelope and
   drags at 350). `panel` 300 → **250 ms**, exactly today's `Durations.medium1`,
   so adopting the token does *not* retune the chat panel — the plan calls that
   animation the reference, so it must come out unchanged.
7. **`PTAnimatedVisibility` was built and then removed.** Every conditional-chrome
   site needed either a size collapse (`AnimatedSize`) or a mount-only entrance
   (`PTEntrance`); shipping an unused primitive into the shared kit is worse than
   not shipping it. `PTShake` and `PTPulse` were added instead, both used.
8. **Buffering scrim now cross-fades** (not in the plan): it popped on *every*
   stall, not just room entry. It is wrapped in `TickerMode` — `Opacity(0)` skips
   painting but does **not** stop tickers, so an always-mounted
   `CircularProgressIndicator` would otherwise drive a repaint every frame for
   the whole session.
9. **Snackbars replaced — added beyond the brief, which never mentions them.**
   See §10.

---

## 10. Toasts (`showPTSnack`, not in the original brief)

`_snack()` was stock Material: no semantic colour, no icon, bottom-centre over
the room's floating control bar, and a queue that stacked one four-second toast
per keypress when you held a blocked key. Four screens plus `main.dart` each had
their own one-line wrapper around `ScaffoldMessenger`.

Now one helper in `lib/ui/banners.dart`, alongside the banner it borrows its
recipe from:

- **`PTSnackKind.info | success | error`** — tinted surface, 1 px semantic
  border, filled semantic glyph. Errors linger 5 s, everything else 3 s. Call
  sites were classified individually; `_snack` defaults to `error` because most
  of them are, and the informational ones (`_blockTransport`'s gate/lock reason,
  transport-lock changes, "no subtitle tracks") pass `.info` explicitly.
- **Solid, never glass.** `ScaffoldMessenger` wraps floating snack bars in a
  `FadeTransition`; a `BackdropFilter` inside one samples an empty layer. This is
  the same trap as §7.1 and the reason the toast follows `PTBanner`'s solid
  tinted-surface recipe rather than `GlassPill`'s.
- **Newest wins** — `clearSnackBars()` before every show, which is what fixes
  the held-key pile-up.
- **`bottomInset`** lifts the toast clear of whatever owns the bottom edge:
  180 / 120 / 70 px for the room's desktop, landscape and portrait layouts. A
  toast landing on the transport controls hides the thing it is talking about.
- **Motion**: the surface still rides `ScaffoldMessenger`'s own slide —
  `SnackBar` exposes no curve override, and at 250 ms `fastOutSlowIn` it is close
  enough to `PTMotion.panel` that replacing the whole mechanism with a custom
  overlay was not worth the queueing, dismissal and a11y behaviour it would give
  up. The glyph settles in via `PTEntrance` a beat after the surface lands, the
  same shell-then-contents order the glass dialogs use.

`SnackBarThemeData` stays in `pt_theme.dart` as a fallback for any future bare
`showSnackBar`, now commented as such.
