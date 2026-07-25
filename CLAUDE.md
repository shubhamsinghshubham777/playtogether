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

There are no tests (no `test/` directory). CI (`.github/workflows/`) is manual-trigger only (`workflow_dispatch`) and builds installers: Windows via `dart run inno_bundle` + Inno Setup (configured in pubspec.yaml under `inno_bundle:`), macOS via DMG. CI uses Flutter 3.38.1 and writes `.env` from the `ENV_FILE` secret.

## Conventions

- Dependency versions in pubspec.yaml are **exact pins** (no `^` ranges) — keep it that way when adding/updating dependencies.
- The code uses Dart's dot-shorthand syntax for enum/static access (e.g. `mainAxisSize: .min`, `_mode = .local`) — requires the pinned SDK; follow this style.
- App version lives in pubspec.yaml `version:`; CI extracts it for installer names.
- **Design system**: dark mode only. All colors/typography come from `lib/ui/pt_theme.dart` (violet glass aesthetic; fonts Space Grotesk / Outfit / JetBrains Mono bundled in `assets/fonts/`; icons via `material_symbols_icons`). Screens must not hardcode hex values — extend `PTColors`/`PTText` instead. Reusable widgets: `lib/ui/` (GlassPanel, PTButton, PTIconButton, PTSlider, PTCodeInput, PTAvatar, PTBanner, showGlassDialog…).
- Error copy is friendly/casual ("Hmm, that doesn't look like a YouTube link."), never raw codes.

## Architecture

Startup (`lib/main.dart`): dotenv → MediaKit → Supabase → `MaterialApp.router` with go_router (`lib/app_router.dart`). Routes: `/login`, `/lobby`, `/profile`, `/room/:id`; a redirect keeps signed-out users on `/login`. The media_kit `Player` is created once in `MainApp` and passed to `RoomScreen`; the `/room/:id` route keys `RoomScreen` by room id — go_router reuses the page for `/room/A → /room/B` (same route pattern), and without the key the old room's State would survive the navigation. `main.dart` also listens for `playtogether://join/<code>` deep links (app_links) **and** checks `getInitialLink()` — the native side replays the launch URL only to the first stream subscriber, which is supabase_flutter (it subscribes inside `Supabase.initialize`), so cold-start invite links never reach the stream listener. If signed out, the code is parked in `RoomService.pendingJoinCode` and consumed by the Lobby after login; if already in a different room, the old membership is left before navigating.

### Backend (`supabase/`)

Migration `…_multi_participant.sql`: `profiles` (auto-created by trigger on signup; guests get `Guest-xxxx`), `rooms` (code, `expires_at`, `ended_at`), `room_members` (role host/member), `messages` (chat, dies with room). All RLS-gated; room channels are **private** Realtime channels (`room:<id>`) authorized via `realtime.messages` policies. RPCs (`security definer`): `create_room` (5–240 min cap, code generation, guest 1-live-room limit), `join_room` (expiry + 8-member cap), `leave_room` (host succession → earliest joiner), `end_room` (host only), `get_server_time` (clock-skew-free countdowns), `delete_account`. pg_cron sweeps expired rooms every minute; a second migration (`…_purge_stale_guests.sql`) purges anonymous users older than 3 days daily and makes `rooms.created_by` cascade on user deletion (without it, `delete_account` and the purge fail for room creators). `supabase/functions/livekit-token` mints LiveKit tokens after checking room membership via the caller's JWT.

Anonymous sign-ins are captcha-gated: Cloudflare Turnstile is enabled server-side (`[auth.captcha]` in `config.toml`, secret via `supabase/.env`), and the client shows a "Quick check" WebView dialog (`lib/auth/turnstile_dialog.dart`, served with baseUrl `http://localhost` — **`localhost` must stay in the Turnstile widget's hostname allow-list**). The client skips the dialog when `TURNSTILE_SITE_KEY` is absent from `.env`, but the server still requires a token, so guest login fails without the key configured.

### Auth (`lib/auth/`), Profile (`lib/profile/`), Rooms (`lib/rooms/`)

`AuthService`: browser `signInWithOAuth(google)` + `playtogether://auth-callback` deep link (registered for macOS/iOS/Android; Windows/Linux registration is an installer concern), `signInAnonymously` for guests, `linkIdentity` to upgrade guest→Google. `ProfileService`/`RoomService` are ChangeNotifier singletons wrapping the tables/RPCs; `RoomService.serverNow` applies the `get_server_time` offset — always use it for expiry math. `RoomScreen` (`lib/rooms/room_screen.dart`) is the room orchestrator: owns playback mode state, countdown/T-5 warning/eviction ("That's a wrap!" popup), banners (reconnecting, file mismatch), chat panel, facecam rail, overflow menu (member list, copy invite, leave, end room), desktop + portrait + landscape layouts.

### Sync layer (`lib/sync/`)

`SyncService` is room-scoped: created on room entry with `(player, room, profile, role)`, disposed on leave. It broadcasts typed events (`sync_events.dart`): play/pause/seek, `state_request`/`state_response`, `mode_switch`, `chat`, `typing`, `position_sync` (host heartbeat every 10 s; members correct if drift > 1.5 s), `file_info` (local-file identity for mismatch banners), `room_ended`.

- **Echo/loop prevention** — three mechanisms, do not break them: channel `self: false`; `_isApplyingRemoteAction` flag (reset after 100 ms settle); last-action-wins timestamp ordering (`_shouldApply`).
- **Late-joiner state sync**: only the **authority** answers `state_request` (host if present, else earliest-joined present member); joiner retries once after 2 s then assumes idle.
- **Presence**: `Stream<List<PresentMember>>` keyed by `user_id` (multi-device users count once); payload carries display name/avatar/role/membership `joined_at` (feeds authority election). Host succession re-tracks presence via `updateRole`.
- **Chat**: rows in `messages` are durable history (loaded on entry, reloaded + fuzzy-merged after every reconnect — broadcasts don't replay); the broadcast is only low-latency fan-out.
- **Reconnection**: on channel error/close, exponential-backoff resubscribe + fresh `state_request`; `connectionStream` drives the "Reconnecting…" banner. Subtlety: `unsubscribe()` reports `closed` back into the subscribe callback, so intentional teardown (`disconnect()`, reconnect cycles) must not be mistaken for a drop — that's what `_tearingDown` and the `identical(channel, _channel)` check guard; removing them recreates an infinite reconnect loop and evicted clients re-joining dead rooms.
- **Dual-player routing**: `RoomScreen` sets `onRemotePlay/Pause/Seek` (+ `onRemoteDriftCorrect`, which must NOT pause YouTube) to route remote actions to the active player, and must call `updatePlaybackState(mode, youtubeUrl)` on mode changes. Every user-initiated play/pause also broadcasts a seek to keep positions aligned. Remote `mode_switch` must dismiss open source/URL dialogs (URL dialog first — it sits on top) without tripping the "re-ask when cancelled" fallback.
- **YouTube intent model** — do not "simplify" this away: `YoutubePlayerController.seekTo` unconditionally calls `play()`, and iframe state transitions land 200–500 ms after commands (far outside the 100 ms settle window). `_ytIntendedPlaying` in `RoomScreen` is the agreed play state: seeks restore it afterwards (`_ytSeekKeepingPlayState`, with a short event-suppression window for the play blip), the player listener only broadcasts transitions that *diverge* from it (direct iframe clicks), and remote commands arriving before the iframe is ready are queued and flushed on the first ready tick (late-joiner sync).

### AV layer (`lib/av/`)

`LiveKitService` (per room): fetches a token from the `livekit-token` edge function, connects to `LIVEKIT_URL`, publishes mic/cam on toggle. Hidden entirely when `LIVEKIT_URL` is unset. Facecam tiles: `lib/rooms/widgets/facecam_rail.dart` (identity = Supabase user id).
