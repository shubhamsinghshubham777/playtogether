<img src="assets/icon/app_icon.svg" width="96" alt="App Icon">

# PlayTogether

Watch stuff together, perfectly in sync. PlayTogether is a Flutter app where you
create a **room**, share a 6-character code (or a `playtogether://join/<code>`
invite link), and everyone's playback stays in lockstep — play, pause, and seeks
broadcast to every member in real time, with chat and live facecams alongside.

<br clear="left">

## Features

- **Rooms** — up to 8 members, join by code or invite link, fixed lifetime
  (5 min – 4 h) with a live countdown, host role with succession when the host
  leaves, and automatic eviction when time's up.
- **Two playback modes** — local video files (via media_kit; each member opens
  their own copy, with a mismatch warning if the files differ) and YouTube.
- **Sync engine** — last-action-wins conflict resolution, authority-answered
  state sync for late joiners, host drift-correction heartbeat, automatic
  reconnection.
- **Chat** — persisted per-room history, typing indicators, unread badge.
- **Facecams** — voice + video tiles powered by LiveKit, with mic/cam toggles.
- **Auth** — Google sign-in or instant guest accounts (Cloudflare Turnstile
  protected); guests can upgrade to Google later without losing their identity.
- **Design** — dark violet glass aesthetic with desktop, portrait, and
  landscape layouts.

Backend: Supabase (Postgres + RLS, private Realtime channels, edge functions,
pg_cron sweeps). AV: LiveKit Cloud.

## Development setup

The Flutter SDK is managed with [fvm](https://fvm.app) — prefix every
`flutter`/`dart` command with `fvm`.

1. `fvm flutter pub get`
2. Copy `.env.example` to `.env` in the repo root and fill in the values
   (Supabase URL + publishable key; `LIVEKIT_URL` and `TURNSTILE_SITE_KEY` are
   optional — facecams and the guest captcha are hidden/skipped when unset).
   The app won't build without a `.env` (it's declared as a Flutter asset).
   **Client-safe values only — `.env` ships inside the app bundle.**
3. `fvm flutter run -d macos` (or `windows`, `linux`, `android`, `ios`)

Lint with `fvm flutter analyze`; release-build with
`fvm flutter build <platform> --release`.

### Backend (Supabase)

Server-side pieces live in `supabase/`. With a linked Supabase CLI:

```bash
supabase db push                                          # schema, RLS, RPCs, cron jobs
supabase functions deploy livekit-token                   # LiveKit token minting
supabase secrets set --env-file supabase/functions/.env   # LiveKit key/secret, see .env.example
supabase config push                                      # auth config (Google OAuth, captcha)
```

Server secrets go in `supabase/functions/.env` and `supabase/.env` (both
gitignored — see the neighbouring `.env.example` files), never in the root
`.env`. Google OAuth needs a Web OAuth client whose redirect URI is
`https://<project-ref>.supabase.co/auth/v1/callback`; the Turnstile widget's
hostname allow-list must include `localhost` (the in-app captcha WebView is
served from there).

### Testing sync on one machine

Room sync needs two identities, but the sandboxed macOS app shares one
container (and thus one session) across instances of the same bundle. Use the
helper:

```bash
fvm flutter run -d macos 2>&1 | tee /tmp/pt-run.log   # instance A
./build/pt-instance-b.sh                              # instance B (logs: /tmp/pt-b.log)
```

The script clones the debug build under a different bundle id so instance B
gets its own sandbox container and guest identity. Re-run it after rebuilds.

## Installers

GitHub Actions (manual trigger) builds a Windows installer (Inno Setup via
`inno_bundle`) and a macOS DMG. The version comes from `pubspec.yaml`. On
Windows/Linux the `playtogether://` URL scheme registration is an installer
concern; macOS/iOS/Android register it via their app manifests.

## Repository layout

| Path | What lives there |
|---|---|
| `lib/ui/` | Design system: theme/tokens, glass panels, buttons, inputs, dialogs |
| `lib/auth/`, `lib/profile/` | Sign-in flows, Turnstile dialog, profile + avatar management |
| `lib/rooms/` | Lobby, room screen and its widgets, room models/service |
| `lib/sync/` | `SyncService` — the realtime sync engine (see `CLAUDE.md` for invariants) |
| `lib/av/` | LiveKit connection + track management |
| `supabase/` | Migrations (schema/RLS/RPCs/cron), edge functions, auth config |

`CLAUDE.md` documents the architecture and the sync-engine invariants in depth.
