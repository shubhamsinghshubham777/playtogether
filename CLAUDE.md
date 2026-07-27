# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PlayTogether is a Flutter app for synchronized ("watch together") media playback across devices. Authenticated users (Google OAuth or anonymous guests) create/join **rooms** (6-char codes or `playtogether://join/<code>` invite links, up to 8 members, fixed expiry ≤ 4 h). Play/pause/seek/mode changes broadcast to all members over a private Supabase Realtime channel per room. Two playback modes: **local** files (media_kit) and **YouTube** (youtube_player_flutter). Rooms also have persisted chat with typing indicators and presence, plus **voice/video facecams** via LiveKit.

## Setup & Commands

This project uses [fvm](https://fvm.app) to manage the Flutter SDK version — **always prefix `flutter` and `dart` commands with `fvm`** (e.g. `fvm flutter run`, `fvm dart run inno_bundle`).

A `.env` file must exist in the repo root before running or building — it is declared as a Flutter asset, so `flutter build`/`run` fail without it. Copy `.env.example` and fill in `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and optionally `LIVEKIT_URL` (facecams) and `TURNSTILE_SITE_KEY` (guest-signup captcha). **Never put server secrets in `.env` — it ships inside the app bundle.** Server-side secrets live in `supabase/functions/.env` and `supabase/.env` (gitignored; see `.env.example` files under `supabase/`).

```bash
fvm flutter pub get                 # install dependencies
fvm flutter run -d macos            # run (or: windows, linux, android, ios)
fvm flutter analyze                 # lint (flutter_lints via analysis_options.yaml)
fvm flutter build macos --release   # release build per platform

supabase db push                    # apply supabase/migrations to the linked project
supabase functions deploy livekit-token
supabase secrets set --env-file supabase/functions/.env   # LiveKit API key/secret
supabase config push                # auth config (needs supabase/.env for Google OAuth + captcha secret)
```

To test room sync on one Mac, run instance A normally and instance B via `./build/pt-instance-b.sh` — the sandboxed app shares one container (= one Supabase session) across instances of the same bundle id, so the script clones the debug build under `app.playtogether.macos.b` to get a second identity. Re-run it after rebuilds; logs go to `/tmp/pt-b.log`.

There are no tests (no `test/` directory). CI (`.github/workflows/`) is manual-trigger only (`workflow_dispatch`) and builds installers: Windows via `dart run inno_bundle` + Inno Setup (configured in pubspec.yaml under `inno_bundle:`), macOS via DMG. CI uses Flutter 3.44.8 and writes `.env` from the `ENV_FILE` secret. `build_windows.yaml` and `build_macos.yaml` hold all the per-platform build logic and are dual-triggered (`workflow_dispatch` + `workflow_call`); `build_installers.yaml` just calls both (`secrets: inherit`) and adds the GitHub release job — so the Flutter version, artifact names, and packaging steps each exist in exactly one place. Their `concurrency` groups carry a `-windows`/`-macos` suffix on purpose: inside a called workflow `github.workflow` resolves to the *caller's* name, so without it the two platform jobs would share one `cancel-in-progress` group and cancel each other.

## Conventions

- Dependency versions in pubspec.yaml are **exact pins** (no `^` ranges) — keep it that way when adding/updating dependencies.
- The code uses Dart's dot-shorthand syntax for enum/static access (e.g. `mainAxisSize: .min`, `_mode = .local`) — requires the pinned SDK; follow this style.
- App version lives in pubspec.yaml `version:`; CI extracts it for installer names.
- **Design system**: dark mode only. All colors/typography come from `lib/ui/pt_theme.dart` (violet glass aesthetic; fonts Space Grotesk / Outfit / JetBrains Mono bundled in `assets/fonts/`; icons via `material_symbols_icons`). Screens must not hardcode hex values — extend `PTColors`/`PTText` instead. Reusable widgets: `lib/ui/` (GlassPanel, PTButton, PTIconButton, PTSlider, PTCodeInput, PTAvatar, PTBanner, showGlassDialog…).
- Error copy is friendly/casual ("Hmm, that doesn't look like a YouTube link."), never raw codes.

## Architecture

Startup (`lib/main.dart`): dotenv → MediaKit → Supabase → `MaterialApp.router` with go_router (`lib/app_router.dart`). Routes: `/login`, `/lobby`, and — **nested under `/lobby`** — `/lobby/profile` and `/lobby/room/:id`; a redirect keeps signed-out users on `/login`. The nesting is load-bearing: it keeps the lobby page underneath, so every `context.go('/lobby')` (back buttons, leave, end room, eviction) shrinks the page stack and plays the *pop* transition — as sibling top-level routes `go` swaps the whole stack and Flutter animates a forward push instead. Build room paths with `roomPath(id)` / parse them with `roomIdOfPath` rather than hand-writing the prefix. Because the room now sits on a stack, `RoomScreen` wraps itself in `PopScope(canPop: false)` and routes a system back gesture through `_leaveRoom()` — a bare pop would skip `leave_room` and strand the membership. The media_kit `Player` is created once in `MainApp` and passed to `RoomScreen`; the room route keys `RoomScreen` by room id — go_router keys pages by route *pattern*, so it reuses the page for room A → room B, and without the key the old room's State would survive the navigation. `main.dart` also listens for `playtogether://join/<code>` deep links (app_links) **and** checks `getInitialLink()` — the native side replays the launch URL only to the first stream subscriber, which is supabase_flutter (it subscribes inside `Supabase.initialize`), so cold-start invite links never reach the stream listener. If signed out, the code is parked in `RoomService.pendingJoinCode` and consumed by the Lobby after login; if already in a different room, the old membership is left before navigating.

### Backend (`supabase/`)

Migration `…_multi_participant.sql`: `profiles` (auto-created by trigger on signup; guests get `Guest-xxxx`), `rooms` (code, `expires_at`, `ended_at`), `room_members` (role host/member), `messages` (chat, dies with room). All RLS-gated; room channels are **private** Realtime channels (`room:<id>`) authorized via `realtime.messages` policies. RPCs (`security definer`): `create_room` (5–240 min cap, code generation, guest 1-live-room limit), `join_room` (expiry + 8-member cap), `leave_room` (host succession → earliest joiner), `end_room` (host only), `get_server_time` (clock-skew-free countdowns), `delete_account`. pg_cron sweeps expired rooms every minute; a second migration (`…_purge_stale_guests.sql`) purges anonymous users older than 3 days daily and makes `rooms.created_by` cascade on user deletion (without it, `delete_account` and the purge fail for room creators). `supabase/functions/livekit-token` mints LiveKit tokens after checking room membership via the caller's JWT.

Anonymous sign-ins are captcha-gated: Cloudflare Turnstile is enabled server-side (`[auth.captcha]` in `config.toml`, secret via `supabase/.env`), and the client shows a "Quick check" WebView dialog (`lib/auth/turnstile_dialog.dart`, served with baseUrl `http://localhost` — **`localhost` must stay in the Turnstile widget's hostname allow-list**). The client skips the dialog when `TURNSTILE_SITE_KEY` is absent from `.env`, but the server still requires a token, so guest login fails without the key configured.

### Auth (`lib/auth/`), Profile (`lib/profile/`), Rooms (`lib/rooms/`)

`AuthService`: browser `signInWithOAuth(google)` + `playtogether://auth-callback` deep link (registered for macOS/iOS/Android; Windows/Linux registration is an installer concern), `signInAnonymously` for guests, `linkIdentity` to upgrade guest→Google. `ProfileService`/`RoomService` are ChangeNotifier singletons wrapping the tables/RPCs; `RoomService.serverNow` applies the `get_server_time` offset — always use it for expiry math. `RoomScreen` (`lib/rooms/room_screen.dart`) is the room orchestrator: owns playback mode state, countdown/T-5 warning/eviction ("That's a wrap!" popup), banners (reconnecting, file mismatch), chat panel, facecam rail, overflow menu (member list, copy invite, leave, end room), desktop + portrait + landscape layouts.

### Sync layer (`lib/sync/`)

`SyncService` is room-scoped: created on room entry with `(player, room, profile, role)`, disposed on leave. It broadcasts typed events (`sync_events.dart`): play/pause/seek, `state_request`/`state_response`, `mode_switch`, `chat`, `typing`, `position_sync` (host heartbeat every 10 s; members correct if drift > 1.5 s), `file_info` (local-file identity for mismatch banners), `room_ended`.

- **Echo/loop prevention** — three mechanisms, do not break them: channel `self: false`; `_isApplyingRemoteAction` flag (reset after 100 ms settle); last-action-wins timestamp ordering (`_shouldApply`).
- **Late-joiner state sync**: only the **authority** answers `state_request` (host if present, else earliest-joined present member) — computed with the *requester excluded*, so when the authority is the one asking (a host reopening their own room) the next in line answers and there is still exactly one responder. Joiner retries once after 2 s then assumes idle. The entry response is answered while the joiner still has the file picker open, so its seek hits an empty player and is lost; `_checkSelfGateSatisfaction` therefore re-requests state on the edge where we *first* have the room's canonical media open. A playing room heals without this (the joiner shuts the gate, everyone pauses at a held position, the reopen seeks back to it) — a room that was already paused broadcasts nothing at all, which is how a late joiner used to end up parked at 0. The resync is skipped when `_roomPlaying`/`_pausedByGate` (the gate resume owns the realignment) or when we're alone.
- **Presence**: `Stream<List<PresentMember>>` keyed by `user_id` (multi-device users count once); payload carries display name/avatar/role/membership `joined_at` (feeds authority election). Host succession re-tracks presence via `updateRole`.
- **Chat**: rows in `messages` are durable history (loaded on entry, reloaded + fuzzy-merged after every reconnect — broadcasts don't replay); the broadcast is only low-latency fan-out.
- **Reconnection**: on channel error/close, exponential-backoff resubscribe + fresh `state_request`; `connectionStream` drives the "Reconnecting…" banner. Subtlety: `unsubscribe()` reports `closed` back into the subscribe callback, so intentional teardown (`disconnect()`, reconnect cycles) must not be mistaken for a drop — that's what `_tearingDown` and the `identical(channel, _channel)` check guard; removing them recreates an infinite reconnect loop and evicted clients re-joining dead rooms.
- **Dual-player routing**: `RoomScreen` sets `onRemotePlay/Pause/Seek` (+ `onRemoteDriftCorrect`, which must NOT pause YouTube) to route remote actions to the active player, and must call `updatePlaybackState(mode, youtubeUrl)` on mode changes. Every user-initiated play/pause also broadcasts a seek to keep positions aligned. Remote `mode_switch` must dismiss open source/URL dialogs (URL dialog first — it sits on top) without tripping the "re-ask when cancelled" fallback.
- **YouTube intent model** — do not "simplify" this away: `YoutubePlayerController.seekTo` unconditionally calls `play()`, and iframe state transitions land 200–500 ms after commands (far outside the 100 ms settle window). `_ytIntendedPlaying` in `RoomScreen` is the agreed play state: seeks restore it afterwards (`_ytSeekKeepingPlayState`, with a short event-suppression window for the play blip), the player listener only broadcasts transitions that *diverge* from it (direct iframe clicks), and remote commands arriving before the iframe is ready are queued and flushed on the first ready tick (late-joiner sync). Two more embed traps: `YoutubePlayer` binds its controller in `initState` and never rebinds — key the widget by `ObjectKey(controller)`, never by URL, and `_switchToYouTubeMode` must early-return on a same-video re-switch or the element drives a disposed controller (dead transport, no duration). YouTube readiness counts `cued` as loaded: `buffered` only updates once a video *plays* (the package's VideoTime poll starts on the playing transition), so a buffered-based check is unreachable for idle members.
- **Known bug (accepted for now)**: the mouse cursor flickers over the room screen in YouTube mode on macOS — see `docs/known-issues.md` before attempting a fix; a Runner-level WKWebView swizzle was tried and reverted. The Dart-side `IgnorePointer` around the embed is not about this: it disables the package's own Flutter touch overlays so taps reach our gesture layer — keep it.
- **Attribution toasts**: `SyncService.remoteActions` emits `RemoteAction` ONLY from the user-initiated play/pause/seek handlers. It must never be fed from `state_response` (which reuses `onRemoteSeek/Play/Pause` — would toast on late-join) or drift correction. Anything user-visible triggered by sync events must keep this user-initiated vs mechanical distinction.

### Room viewing UX (`RoomScreen` + `room_control_bar.dart`)

- **Keyboard/focus**: shortcuts are ignored while any `EditableText` has focus. Esc consumers are strictly ordered — text-field unfocus → chat close → fullscreen exit — and new Esc handlers must slot into that order explicitly; whatever closes must hand focus back to `_shortcutFocus`.
- **Desktop single-tap on the video is intentionally instant**: no `onDoubleTap` on that gesture detector (double-tap recognition adds ~300 ms lag; a deliberate product call). Touch layouts get double-tap ±10 s skip zones instead; double-click-fullscreen was rejected for the same reason — fullscreen is F/Esc via `window_manager` (desktop only, gated by `lib/platform.dart`; a `WindowListener` keeps the flag synced with native green-button transitions).
- **Glass rendering trap**: wrapping `GlassPanel` in `Opacity` makes its `BackdropFilter` blur an empty layer — animate glass surfaces by sliding/clipping, never fading (see the chat panel's `_chatAnim`). A collapsed overlay in a `Positioned` still fills its slot (tight constraints) and eats clicks — wrap the zero state in `IgnorePointer`.
- **Broadcast on gesture end, preview locally during** (scrub `_dragValue` pattern) — never broadcast per-tick.

### Readiness gate (`lib/sync/` + `RoomScreen` + `readiness_overlay.dart`)

Nobody can start or scrub until **every present member** has the room's canonical media loaded. Strict lockstep: a member swapping files mid-play, or a late joiner, system-pauses everyone; when the gate reopens, playback auto-resumes at the held position.

- **Canonical media is room-level and host-only.** `rooms.media_kind/media_name/media_duration_ms/media_url/media_updated_at`, written solely by the `set_room_media` RPC (host + live-room enforced server-side; a `rooms_media_shape_chk` constraint keeps per-kind fields null). The row is the source of truth — it survives host succession and reaches late joiners; the `media_set` broadcast is only fan-out. Clients refetch the row on entry and on **every** resubscribe. `RoomMedia.isNewerThan` (keyed on the **server** clock `media_updated_at`, never `SyncEvent.timestamp`) stops a late-resolving refetch from clobbering a newer broadcast.
- **Readiness rides on presence** (`ready_status`, `loaded_file_name`), because presence replays to joiners and dies with the connection — a member who drops stops holding the gate shut. `retrackReadiness` mirrors `updateRole`. `ReadyStatus`'s declaration order IS its rank: the multi-device merge keeps the *most ready* device. Reconnect needs no extra code — `_readyStatus` survives, and the subscribe callback already re-tracks.
- **`ready` means "a file is open", not "the right file".** The name comparison lives in `memberSatisfiesGate`, which is what lets the UI distinguish "Loading" from "Wrong file (name)".
- **`gateState` is tri-state.** `indeterminate` until the first presence sync — render it as *usable*, never as closed, or every room entry flashes the overlay.
- **Only the authority emits derived actions** (`_evaluateGate`), else eight clients broadcast the same pause. The decision uses `_roomPlaying` (room-level), **not** `isPlaying` (our own player) — when the host opens a new file their player stops while everyone else plays on, which is exactly when the gate must pause. `_pausedByGate` is tracked on **every** client so host succession mid-wait doesn't lose auto-resume; any human play/pause clears it, so auto-resume never overrides a deliberate pause. The held resume position is dropped when *we* are the blocker (our position is about some other file).
- **Gate-derived play/pause carry `reason: 'gate'` and never raise attribution toasts** — that's the `remoteActions` user-initiated-only invariant.
- **Every broadcast stamps itself via `_nextTimestamp()`**, never `DateTime.now()`. `_shouldApply` drops `timestamp <= _lastAppliedTimestamp`, and `_playPause` sends play *and* seek in one synchronous block — same-millisecond collisions silently ate the second event.
- **Transport lock** (`rooms.transport_lock`, `set_transport_lock`): host-only remote. Enforced at the same choke points as the gate.
- **Gate at the choke points, not the widgets** — `_playPause`/`_seek` (and `_skip` via `_seek`) cover keyboard shortcuts and double-tap skip zones, which never touch the control bar. `transportEnabled`/`transportHint` are affordance only.
- **Kick/ban**: `kick_member(room_id, target, ban)` + `room_bans`; the ban check in `join_room` sits *before* the already-a-member early return. Deleting the membership row does **not** eject anyone — Realtime authorizes at *subscribe* time — so the `member_kicked` broadcast is load-bearing.

### AV layer (`lib/av/`)

`LiveKitService` (per room): fetches a token from the `livekit-token` edge function, connects to `LIVEKIT_URL`, publishes mic/cam on toggle. Hidden entirely when `LIVEKIT_URL` is unset. Facecam tiles: `lib/rooms/widgets/facecam_rail.dart` (identity = Supabase user id).
