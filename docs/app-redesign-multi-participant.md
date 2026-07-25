# PlayTogether — App Redesign + Multi-Participant Overhaul — LIVING DOC

> **Read §0–§3 before touching any code.** Single source of truth for this
> initiative. Code is the source of truth; this doc is hypotheses.
>
> Any instance (Claude or human) picking this up:
> 1. Read §0 (mission), §1 (working agreement), §3 (audit board), and the LAST §8 entry.
> 2. Pick the first unchecked §3 item NOT gated on an unanswered §4 decision.
> 3. Grill the user (A/B/C options) before building.
> 4. Update §3 + append a §8 entry as the LAST step of every session.
> 5. At ~50–60% context usage, STOP and write a §8 handoff (template at top of §8).

---

## 0. Mission & non-goals

**Mission.** Implement `docs/multi-participant-plan.md` (v2, all decisions locked §9)
**and** the full visual redesign from the Claude Design project "Playtogether redesign"
(local export: `/Users/shubham-nc/Downloads/playtogether-redesign/project/*.dc.html` —
read the HTML/CSS directly; recreate pixel-perfect in Flutter, don't copy DOM structure).
Done = authenticated (Google + guest) room-based watch-together app with up to 8
members, private Realtime channels, persisted chat, room expiry/eviction, **LiveKit
voice+video facecams**, in the dark glass/violet design — desktop + mobile portrait +
mobile landscape layouts, `fvm flutter analyze` clean.

**You are responsible for the success of this initiative.** Audit your own area and
harden edge cases. Update §3 when you discover new work.

### Non-goals (DO NOT do these)
- Apple login (deferred, plan §9.9). No iOS App Store release this initiative.
- Light theme (design system rule: dark only).
- Native google_sign_in SDK flows (browser OAuth + deep link only, plan Phase 1).
- Room extension UI/RPC (plan §9.4 — expiry fixed at creation).
- File streaming/verification for local mode (name+duration mismatch banner only).
- Supabase Pro migration (free tier during dev, plan §9.7).

---

## 1. Working agreement

1. Code is the single source of truth. Verify every claim against the tree before acting.
2. One in-progress §3 item at a time. Finish or hand off first.
3. Append-only §8. Never rewrite past entries.
4. At ~50–60% context usage, STOP and write a §8 handoff.
5. Update §3 + §8 as the LAST step of every session.
6. Dates are absolute (YYYY-MM-DD).
7. Grill before building — A/B/C options. Park unresolved calls in §4.
8. Project rules: prefix all flutter/dart with `fvm`; **exact-pin** all pubspec deps
   (no `^`); Dart dot-shorthand style (`.min`, `_mode = .local`); no AI co-author
   lines in commits; **NEVER read `.env`** (read `.env.example` only); lint gate =
   `fvm flutter analyze`. Supabase CLI is authenticated + linked to project
   `qyxwdjnwsklpljxtpewh` (ap-south-1). Secrets: client-safe values go in `.env`
   (it is a bundled Flutter asset!); server secrets go in `supabase/functions/.env`
   (gitignored) and are pushed with `supabase secrets set --env-file` without reading.
9. The closing instance deletes this doc (`git rm docs/app-redesign-multi-participant.md`)
   **before** opening the PR. Migrate durable notes into README/CLAUDE.md first.

---

## 2. Architecture as-it-is (verified against `main` on 2026-07-24)

Startup: `lib/main.dart` → dotenv → MediaKit → Supabase.init → `MainApp` (creates
media_kit `Player` once) → `UsernameDialog` (hardcoded "Reet"/"Shubh") →
`SyncService(player, username)` on channel `playtogether:default` (public, `self:false`)
→ `PTVideoPlayer(player, syncService)`.

- `lib/sync/sync_service.dart` (330 ln): broadcast events, 2-peer presence bool,
  in-memory chat history, echo-prevention (`self:false` + `_isApplyingRemoteAction`
  + last-action-wins `_shouldApply`), first-response-wins state sync.
- `lib/sync/sync_events.dart` (220 ln): sealed event classes; chat carries `username`.
- `lib/player/pt_video_player.dart` (748 ln): mode state (local/youtube), dialog-open
  flags dismissed on remote mode_switch, `_PTVideoPlayerControls` (keyboard shortcuts),
  chat side panel w/ unread badge. Play/pause also broadcast seek.
- `lib/player/youtube_controls.dart`, `chooser_dialog.dart`, `mode_selection_dialog.dart`,
  `youtube_url_dialog.dart`, `progress_section.dart`; `lib/chat/chat_box.dart` (295 ln).
- Theme: flex_color_scheme cyanM3 dark (will be replaced).
- No `test/`, no `supabase/` dir yet. CI = manual installer builds, Flutter 3.38.1.

### Design references (read these, not screenshots)
| Screen | File (in redesign bundle `project/`) |
|---|---|
| Tokens/components/rules | `Design System.dc.html` (colors, type, glass recipe, voice) |
| Login / Lobby / Profile / Room | `<Name>.dc.html` — each has desktop 1440×900 + portrait 390×844 + landscape 844×390 |
| Dialogs, banners, guest-limit | `Dialogs.dc.html` |

Key tokens: primary #8B5CF6, gradient #8B5CF6→#A855F7 (buttons) / →#C084FC (bars),
text-accent #C9B8FF, canvas #08070C, screen bg #0B0A14, glass rgba(22,18,38,.5–.6)
+ blur 28–32 + border white .13, dialog glass rgba(24,19,42,.75–.85), online #4ADE80,
warn/host #FDE68A, danger #FCA5A5. Fonts: Space Grotesk (headings), Outfit (body),
JetBrains Mono (codes/time). Icons: Material Symbols Rounded (filled).

---

## 3. Audit board (tick as completed; ONE in-progress at a time)

> Legend: `[ ]` todo · `[~]` in progress · `[x]` done+verified ·
> `[?]` needs repro/logs · `[G]` blocked on a §4 decision.

### A — Backend infra (Supabase; plan Phase 0)
- [x] **A1. Supabase project scaffolding.** `supabase init`; `config.toml` with
  anonymous sign-ins on, Google external provider via `env(...)`, site_url +
  `playtogether://auth-callback` + `playtogether://join/*` redirect allow-list;
  `supabase/functions/.env.example`; gitignore `supabase/functions/.env`, `supabase/.env`.
- [x] **A2. Migration 0001 — schema + RLS + RPCs.** (pushed to remote 2026-07-24) Tables profiles/rooms/room_members/
  messages per plan §2 SQL; signup trigger (Google seed vs Guest-xxxx); RLS per plan;
  `realtime.messages` policy for topic `room:<id>` members-only; RPCs `create_room`
  (240-min cap, unambiguous 6-char code, guest 1-live-room limit), `join_room` (expiry +
  8-cap), `leave_room` (host succession by earliest joined_at), `end_room` (host only),
  `get_server_time`, `delete_account` (security definer). pg_cron every-minute sweep
  setting `ended_at`.
- [x] **A3. Avatars storage bucket.** (in migration 0001) Public read, authenticated write `avatars/{uid}.jpg`,
  ~2 MB limit (bucket + storage.objects policies in migration).
- [~] **A4. Push to remote.** db push + function deploy DONE; `config push` + `secrets set` remain (gated on §4 Q2/Q3 env files). `supabase db push`; `supabase config push` (needs Google
  OAuth client creds in `supabase/.env` — see §4 Q2); `supabase secrets set --env-file
  supabase/functions/.env` (LiveKit keys). Verify with `supabase migration list`.
- [x] **A5. LiveKit token edge function.** (deployed; secrets pending Q3) `supabase/functions/livekit-token`: verifies
  the caller's Supabase JWT, checks room membership in DB, mints LiveKit access token
  (room = room id, identity = user id, name = display_name); deploy.

### B — App foundation
- [x] **B1. Dependencies + fonts.** (supabase_flutter→2.16.0, uuid→4.6.0 to satisfy pins) Exact-pin: go_router, app_links, responsive_framework,
  livekit_client, image, material_symbols_icons; bundle Space Grotesk/Outfit/JetBrains
  Mono TTFs in `assets/fonts/` + pubspec `fonts:` section. `.env.example` gains
  `LIVEKIT_URL`. Keep media_kit/youtube/supabase pins.
- [x] **B2. Design system in Flutter.** (lib/ui/: pt_theme, glass, buttons, inputs, identity, banners) `lib/ui/` — `pt_theme.dart` (ThemeData from §2
  tokens), `glass.dart` (GlassPanel/pill; BackdropFilter recipe), buttons (primary
  gradient / secondary / destructive / icon 44 / play 58), inputs (+focus/error),
  segmented code boxes, slider theme, badges (code pill, Host, Guest), gradient avatar
  (per-user fixed gradient + presence dot + stack), chat bubbles, tinted banners
  (warn/info/error), glass dialog shell, ambient-glow background, typing dots.
- [x] **B3. Routing + responsive scaffolding.** (lib/app_router.dart, lib/ui/responsive.dart) go_router (`/login`, `/lobby`, `/profile`,
  `/room/:id`) with auth redirect; responsive_framework breakpoints (desktop ≥ ~840,
  else portrait/landscape by orientation) + per-screen layout switcher.

### C — Auth (plan Phase 1)
- [x] **C1. AuthService + AuthGate.** (auth_service.dart; gate = router redirect) signInWithOAuth(Google, redirect
  `playtogether://auth-callback`), signInAnonymously, signOut, authStateStream;
  session-expiry → login (single `signedOut` branch + 401 defensive check).
- [~] **C2. Deep links.** macOS/iOS/Android registered + app_links listener in main.dart. Windows (installer registry) + Linux (.desktop x-scheme-handler) deferred to packaging — see §8. app_links; register `playtogether://` scheme:
  AndroidManifest, iOS + macOS Info.plist, Windows/Linux runner registration.
- [x] **C3. Login screen** per `Login.dc.html` (3 layouts, Google SVG button, guest
  button, terms fine print, error surface, loading states).
- [x] **C4. Remove username_dialog.dart + main.dart bootstrap swap.** Player creation
  stays app-level; SyncService no longer created at startup.

### D — Profile (plan Phase 2)
- [x] **D1. ProfileService.** fetch/update profile; avatar pick (fast_file_picker) →
  `image` downscale/crop 512×512 JPEG → Storage upload → avatar_url + cache-bust.
- [x] **D2. Profile screen** per `Profile.dc.html`: avatar w/ camera affordance, editable
  display name, locked email row, logout, delete-account (confirm → RPC → sign-out);
  guest variant (locked fields, "Keep your identity" Google card via linkIdentity,
  "End guest session"); first-login display-name prompt if OAuth gave none.

### E — Rooms & Lobby (plan Phase 3)
- [x] **E1. Room models + RoomService.** Room/RoomMember; RPC wrappers; current-room
  state; member-list stream (postgres_changes or refetch on presence).
- [x] **E2. Lobby screen** per `Lobby.dc.html`: greeting, create card (name field,
  duration slider 5–240 default 150, gradient CTA), join card (6 segmented code boxes,
  invite-link info banner), header (profile pill, logout).
- [x] **E3. Invite deep links.** (main.dart listener + pendingJoinCode funnel) `playtogether://join/<code>` → join_room funnel (works
  logged-out → after login/guest, resume join).
- [x] **E4. Guest room-limit dialog** per `Dialogs.dc.html` ("One room at a time",
  End that room / Rejoin it).

### F — Room screen & sync refactor (plan Phase 4 — HIGH RISK)
- [x] **F1. SyncService rewrite (room-scoped).** `SyncService(player, room, profile)`;
  private channel `room:<id>`; senderId = auth uid; keep echo-prevention trio;
  presence → `Stream<List<PresentMember>>` keyed by user_id; typing = set of ids
  with per-user timeouts.
- [x] **F2. Chat persistence.** Insert into `messages` + broadcast; load history on
  entry; kill in-memory `_chatHistory`.
- [x] **F3. Authority state sync + drift correction.** Only authority answers
  state_request (host if present, else earliest-joined present); 2 s timeout, one
  retry, then idle. Host broadcasts `position_sync` every 10 s while playing; members
  correct if |drift| > 1.5 s.
- [x] **F4. Room screen UI** per `Room.dc.html` desktop: room pill (name, copyable code,
  countdown), chat panel (330 w, header "N watching", close), glass control bar (progress,
  replay10/play58/forward10, audio/subtitle/source/file buttons, volume), overflow menu
  (member list w/ presence + Host badge, copy invite, leave, end-room destructive),
  unread badge. Preserve keyboard shortcuts + dialog-dismissal-on-remote-switch logic.
- [x] **F5. Dialog restyles** per `Dialogs.dc.html`: source chooser ("What are we
  watching?"), YouTube URL (+ inline validation error), subtitle/audio track chooser.
- [x] **F6. File-mismatch banner.** Broadcast file name+duration on local load; mismatch
  → red banner w/ "Pick file".
- [x] **F7. Room mobile layouts.** Portrait (header/video/cam-strip/controls/chat column),
  landscape (immersive fullscreen, pill top-left, floating pill control bar, safe areas).

### G — Expiry & eviction (plan Phase 5)
- [x] **G1. Countdown + T-5 warning.** get_server_time offset once; local ticker;
  amber banner at T-5 ("ends at <time>").
- [x] **G2. Eviction.** At zero or `room_ended` broadcast: pause, unsubscribe, blocking
  "That's a wrap!" popup (desktop dialog / mobile bottom sheet) → lobby. Checks on app
  resume + failed RPC; join of ended room fails gracefully.

### H — LiveKit voice/video (NEW vs plan; user-approved scope)
- [x] **H1. LiveKitService.** (lib/av/livekit_service.dart; end-to-end test gated on Q3) Fetch token from edge function; connect to `LIVEKIT_URL`;
  publish/unpublish mic + cam; local+remote track streams; speaking events; dispose on
  leave. Env: client `.env` → `LIVEKIT_URL`; server secrets → §4 Q3.
- [x] **H2. Facecam UI.** (lib/rooms/widgets/facecam_rail.dart; entitlements + permissions added for macOS/iOS/Android) Desktop left rail 200 w (self tile violet-ring + "You" +
  speaking eq, video tiles w/ name pill + mic_off chip, avatar tile when cam off,
  reconnecting tile at 60% opacity, "Hide cams" pill); mobile strip / landscape
  mini-stack + "+N" overflow. Mic/cam toggle buttons (active = violet .3 fill) in
  control bar. Permission prompts + denial states.
- [~] **H3. AV lifecycle hardening.** Reconnect states surfaced; device hot-swap + denial UX untested (needs Q3 creds + real devices). Reconnect, device hot-swap, guest identity names,
  leave/end cleanup, ≤8 participants.

### I — Hardening & cleanup
- [x] **I1. Realtime reconnection.** (backoff resubscribe + re-request state + banner, sync_service.dart) channelError/closed → resubscribe w/ backoff,
  re-request state, "Reconnecting…" info banner (design exists).
- [ ] **I2. Dead code + analyze.** Remove username_dialog, flex_color_scheme dep if
  unused, stale strings; `fvm flutter analyze` clean; README/CLAUDE.md updates.
- [ ] **I3. 3-device manual test script** (write + run; recipes in §6).

---

## 4. Open decisions to grill

- **Q1. RESOLVED 2026-07-24 (all four, by user):** LiveKit = full SDK support;
  Supabase via linked CLI; layouts = desktop + mobile with a well-known responsive
  package; tracking doc = this file.
- **Q2. Google OAuth client.** User must create a Web OAuth client in Google Cloud
  console (authorized redirect: `https://qyxwdjnwsklpljxtpewh.supabase.co/auth/v1/callback`)
  and put `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` / `..._SECRET` into `supabase/.env`
  (gitignored). Gates: A4 (config push), C1 end-to-end test. Guest flow works without it.
- **Q3. LiveKit credentials.** User adds to `.env`: `LIVEKIT_URL=wss://<proj>.livekit.cloud`;
  and to `supabase/functions/.env`: `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
  (server-only — must NOT go in `.env` because `.env` is a bundled asset). Gates: A4
  secrets, H1 end-to-end test. UI work is not gated.

---

## 5. (reserved)

---

## 6. Device/manual test recipes

### R-1. Auth smoke (macOS)
1. `fvm flutter run -d macos` → Login screen renders (glass card, glow blobs).
2. "Continue as guest" → Lobby greets "Hey Guest-xxxx". Relaunch → still signed in.
3. Profile → guest variant locked; "End guest session" → Login.

### R-2. Rooms 2-device (macOS + second device/build)
1. Device A: create room (name, 30 min) → Room; code pill visible; countdown sane.
2. Device B: join via code → both see 2 members w/ presence dots.
3. A picks YouTube URL → B switches; play/pause/seek both directions stay in sync.
4. B closes app → A member list marks B away. B rejoins via invite link.
5. Host A leaves → B promoted host (overflow shows Host badge + End room).

### R-3. Expiry (create 5-min room)
1. T-5 amber banner immediately (5-min room). At zero both get "That's a wrap!" → lobby.
2. Rejoin by old code → friendly failure.

### R-4. LiveKit (2 devices in room)
1. Enable cam+mic on A → B sees A's tile video + speaking eq when A talks.
2. A mutes → B sees mic_off chip. A cam off → avatar tile. ≤8 enforced.

---

## 7. Robustness patterns to adopt

- Never trust client clock: all expiry math via `get_server_time` offset; server RLS
  enforces regardless.
- Every RPC error mapped to friendly copy (design voice: "Hmm, that doesn't look
  like…" not "Error 409").
- Keep the echo-prevention trio intact through the sync rewrite (self:false analogue,
  `_isApplyingRemoteAction`, last-action-wins) — regressions here are the top risk.
- Widgets read design tokens from `lib/ui/pt_theme.dart` only — no inline hex in screens.

---

## 8. Findings & handoff log (append-only — newest at BOTTOM)

### Handoff prompt template (copy, fill, paste for the next instance)
```
You are continuing the PlayTogether redesign+multi-participant initiative. Read
docs/app-redesign-multi-participant.md §0–§3 (code is source of truth). Current
branch: <branch>. Last completed: <item>. In progress: <item> — <state, files,
what's left>. Blocked-on grills: <Q#s>. Test status: <...>.
NEXT: <single next action>. Follow §1 working agreement.
```

### 2026-07-24 (session 1, part 2) — full implementation pass (see bottom for init entry)

What shipped (all verified by `fvm flutter analyze` clean + `fvm flutter build macos --debug` exit 0):
- Backend live on remote: migration `20260724100000_multi_participant.sql` applied
  (`supabase migration list` shows it synced), `livekit-token` deployed. NOTE: local
  network is IPv4-only — `supabase link --project-ref qyxwdjnwsklpljxtpewh` was re-run
  to use the pooler; do the same if `db push` says "IPv6 not supported".
- New app shell: lib/ui/* design system, go_router in lib/app_router.dart,
  main.dart rewritten (deep links + pendingJoinCode funnel), username_dialog deleted.
- Screens: login, lobby (create/join/guest-limit), profile (account + guest variants),
  room_screen.dart (desktop/portrait/landscape) + widgets/ (chat panel, control bar,
  overflow menu, facecam rail) + restyled dialogs in lib/player/.
- Sync rewrite: lib/sync/* per plan Phase 4 (authority answers, position_sync drift,
  chat persisted in messages table, typing set, presence keyed by user_id,
  reconnect backoff). Echo-prevention trio preserved.
- LiveKit: lib/av/livekit_service.dart + facecam UI; camera/mic entitlements
  (macOS Debug+Release), NSCamera/NSMicrophoneUsageDescription (macOS/iOS),
  Android permissions. macOS also gained com.apple.security.network.client
  (was missing entirely — outgoing sandbox networking).
- Deps: +go_router 17.3.0, app_links 7.2.1, responsive_framework 1.5.1,
  livekit_client 2.8.1, image 4.9.1, material_symbols_icons 4.2960.0;
  supabase_flutter 2.12.0→2.16.0, uuid→4.6.0; -flex_color_scheme. Fonts bundled.
- CLAUDE.md rewritten to match the new architecture.

What was ruled out / gotchas for the next instance:
- supabase_flutter 2.12.0 pins app_links ^6; bumped supabase_flutter instead of
  downgrading app_links (7.x needed nothing special).
- `flutter build macos` works headless; `pt_video_player.dart`, `youtube_controls.dart`,
  `progress_section.dart`, `chat_box.dart` are DELETED — their delicate logic lives in
  room_screen.dart (dialog-dismissal order, broadcast-seek-with-playpause, yt listener).
- Windows/Linux `playtogether://` registration still missing (installer/.desktop task).

Not yet verified on devices: everything in §6 (R-1…R-4). Auth E2E needs Q2 creds;
LiveKit E2E needs Q3 creds. `config push` + `secrets set` are the only remaining
backend steps (exact commands in §4 Q2/Q3 + README of supabase/.env.example files).

NEXT: user fills `.env` (LIVEKIT_URL), `supabase/.env` (Google OAuth), and
`supabase/functions/.env` (LiveKit key/secret); then run
`set -a; source supabase/.env; set +a; supabase config push` and
`supabase secrets set --env-file supabase/functions/.env`; then run §6 R-1/R-2 on
macOS. Fix whatever the manual pass surfaces.

### 2026-07-25 (session 2) — backend live-verified; first UI bug found+fixed
- A4 completed: `supabase config push` (auth: updated; had to set `[storage.vector]
  enabled = false` — free tier 402s on it — and un-escape the sms template lines)
  and `supabase secrets set` (3 LiveKit vars) both green.
- Full REST smoke against prod passed: anon signup → profile trigger (Guest-bd18),
  create_room (code XFGRXD), guest_room_limit, join_room, RLS member list,
  room_not_found, livekit-token (real 408-char JWT), get_server_time, not_host,
  end_room, room_ended-on-rejoin. All exactly per plan.
- UI smoke (macOS): login renders (portrait + desktop variants confirmed);
  guest sign-in navigates to lobby; lobby desktop layout CRASHED black —
  `Row(crossAxisAlignment: .stretch)` inside vertical SingleChildScrollView →
  infinite height (lobby_screen.dart:180). FIXED with IntrinsicHeight wrapper.
  Lesson: audit any `.stretch` Row/Column inside scroll views (landscape lobby
  uses Expanded — safe; checked others).
- User will run the §6 recipes manually and report logs.
- OPEN (user question): captcha on anonymous sign-ins — see final report options;
  per-IP rate limit (30/hr) already active via config; stale-anon purge cron is
  the recommended cheap mitigation, awaiting user pick.
- Memory + this doc are TEMPORARY: after user approval → migrate durable notes to
  README.md/CLAUDE.md, delete doc + memory (user instruction 2026-07-25).

### 2026-07-25 (session 2b) — anti-abuse: guest purge cron + Turnstile captcha
- Migration `20260725110000_purge_stale_guests.sql` pushed: daily 03:17 UTC purge of
  anonymous users older than 3 days, plus FK fix — rooms.created_by now cascades
  (without it, delete_account and the purge failed for any user who created a room).
  NOTE: db push needed `SUPABASE_DB_PASSWORD` this session (CLI login-role 400s).
- Turnstile enabled end-to-end: `[auth.captcha]` (provider turnstile) pushed to remote
  (secret via supabase/.env env-substitution); client shows a "Quick check" glass
  dialog (lib/auth/turnstile_dialog.dart) hosting the widget in flutter_inappwebview
  (now a direct dep, 6.1.5) with baseUrl http://localhost — `localhost` MUST stay in
  the Cloudflare widget's hostname allow-list. Token → signInAnonymously(captchaToken).
  Flow is skipped when TURNSTILE_SITE_KEY is absent from .env — but the SERVER now
  always requires a token, so guest login without the key configured will fail
  (Linux caveat: no webview → decide later: disable captcha, or gate guest button).
- .env gains TURNSTILE_SITE_KEY; supabase/.env gains SUPABASE_AUTH_CAPTCHA_SECRET
  (both .example files updated by user).
- Lobby IntrinsicHeight crash-fix from session 2 still awaiting the user's manual
  §6 recipe pass. Analyze clean; macOS debug build re-verified after webview dep.

### 2026-07-25 (session 2c) — user-verified: guest flow + captcha + lobby GREEN
- User ran R-1 with Turnstile enabled: clean log, "guest mode ran perfectly" —
  login → Quick check → lobby all working. Lobby IntrinsicHeight fix confirmed.
- Committed all work to main at this point (no push).
- REMAINING before user approval: manual R-2 (2-instance rooms/sync/chat/facecams),
  R-3 (expiry), R-4 (invite link), Google OAuth E2E (Q2 creds are configured,
  flow untested), LiveKit E2E. After approval: write README.md, final CLAUDE.md
  pass, delete this doc + the temporary memory (user instruction).

### 2026-07-24 (session 1) — initialized
- Scaffolded living doc. Read plan + all 6 design files (MCP project b0cf7228… ==
  local bundle export, verified identical file lists; using local copies).
- User decisions captured (§4 Q1): LiveKit full, CLI-driven Supabase, responsive
  desktop+mobile, doc in docs/.
- Verified: supabase CLI 2.109.1 authenticated, project qyxwdjnwsklpljxtpewh linked;
  fvm Flutter 3.44.8 / Dart 3.12.2.
- §3 seeded A–I. §4 open: Q2 (Google OAuth creds), Q3 (LiveKit creds) — user to fill
  env files; everything else unblocked.
- NEXT: A1 (supabase scaffolding), then A2 migration, then B1 deps/fonts.
