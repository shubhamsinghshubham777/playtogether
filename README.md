<img src="assets/icon/app_icon.svg" width="96" alt="App Icon">

# PlayTogether

Watch stuff together, perfectly in sync. PlayTogether is a Flutter app where you
create a **room**, share a 6-character code (or a `playtogether://join/<code>`
invite link), and everyone's playback stays in lockstep — play, pause, and seeks
broadcast to every member in real time, with chat and live facecams alongside.

# Preview

| Screen | Preview |
|---|---|
| Splash | <img src="https://github.com/user-attachments/assets/f6be89db-907d-4b2e-8553-87a2339f1e96" /> |
| Home | <img src="https://github.com/user-attachments/assets/cbd1b2ae-ba97-48ec-8636-dd2fc29b03a8" /> |
| Room | <img src="https://github.com/user-attachments/assets/520ddc80-dcb9-4588-a05e-9167e59ec2ca" /> |


## Features

- **Tiers & Room Limits** — Guest (up to 4 members, 1 h session), Free (up to 8 members, 4 h session, voice facecams, 24 h dormant room retention with 1 free 60-min extension), and Premium (up to 16 members, 24 h sessions, video facecams at 360p, persistent rooms, full extended animated reactions, custom duration extensions).
- **Resumable Rooms** — Dormant rooms can be resumed by the host from the lobby with playback position seamlessly restored, or ended/deleted by the room creator.
- **Two Playback Modes** — local video files (via media_kit; each member opens their own copy, with a mismatch warning if the files differ) and YouTube (via custom IFrame bridge).
- **Sync Engine** — strict lockstep readiness gate, last-action-wins conflict resolution, authority-answered state sync for late joiners, host drift-correction heartbeat, automatic reconnection.
- **Chat** — persisted per-room history, typing indicators, unread badge.
- **Quick Reactions** — Meet-style animated Noto Emoji (8 core bundled, extended collection streamed on demand via CDN with cryptographic SHA-256 verification for Premium).
- **Facecams** — LiveKit-powered voice (Free/Premium) and video (Premium) tiles, with mic/cam toggles.
- **Web & Subscriptions** — Next.js 15 marketing site and account portal (`website/`) with Paddle Billing checkout and real-time subscription reactivity in the Flutter client.
- **Auth** — Google sign-in or instant guest accounts (Cloudflare Turnstile protected); guests can upgrade to Google in-place without losing their identity.
- **Self-Updating Desktop** — macOS and Windows check for new releases on launch and offer a one-click "update & restart" from the lobby.
- **Design** — dark violet glass aesthetic with desktop, portrait, and landscape layouts.

Backend: Supabase (Postgres + RLS, private Realtime channels, edge functions, pg_cron sweeps). AV: LiveKit Cloud. Billing: Paddle Merchant of Record.

## Development setup

### Flutter App

The Flutter SDK is managed with [fvm](https://fvm.app) — prefix every
`flutter`/`dart` command with `fvm`.

1. `fvm flutter pub get`
2. Copy `.env.example` to `.env` in the repo root and fill in the values
   (Supabase URL + publishable key; `LIVEKIT_URL` and `TURNSTILE_SITE_KEY` are
   optional — facecams and the guest captcha are hidden/skipped when unset).
   The app won't build without a `.env` (it's declared as a Flutter asset).
   **Client-safe values only — `.env` ships inside the app bundle.**
3. `fvm flutter run -d macos` (or `windows`, `linux`, `android`, `ios`)

Lint with `fvm flutter analyze`; test with `fvm flutter test`; release-build with
`fvm flutter build <platform> --release`.

### Web App & Subscriptions (`website/`)

The marketing site, download portal, and subscription checkout live in `website/`:

```bash
cd website
npm install
cp .env.example .env.local    # configure Supabase + Paddle sandbox credentials
npm run dev                   # start Next.js 15 server at http://localhost:3000
npm test                      # run webhook deduplication & signature tests
```

To test Paddle webhooks locally, use Hookdeck or the Paddle CLI:
```bash
hookdeck listen 3000 playtogether-webhooks --path /api/paddle/webhook
```

### Backend (Supabase)

Server-side pieces live in `supabase/`. With a linked Supabase CLI:

```bash
supabase db push                                          # schema, RLS, RPCs, cron jobs
supabase functions deploy livekit-token                   # LiveKit token minting
supabase secrets set --env-file supabase/functions/.env   # LiveKit key/secret, see .env.example
supabase config push                                      # auth config (Google OAuth, captcha, redirect URLs)
```

Server secrets go in `supabase/functions/.env` and `supabase/.env` (both
gitignored — see the neighbouring `.env.example` files), never in the root
`.env`. Google OAuth needs a Web OAuth client whose redirect URI is
`https://<project-ref>.supabase.co/auth/v1/callback`; the Turnstile widget's
hostname allow-list must include `localhost` (the in-app captcha WebView is
served from there).

### Testing sync on one machine

Room sync needs two identities, but the macOS app shares one
preferences domain across instances of the same bundle id. Use the
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

The same run also publishes a signed `appcast.xml`, which is how installed
desktop builds update themselves (Sparkle on macOS, WinSparkle on Windows).
Pre-releases are excluded from that feed, so they never reach existing installs.

## Repository layout

| Path | What lives there |
|---|---|
| `lib/ui/` | Design system: theme/tokens, glass panels, buttons, inputs, dialogs |
| `lib/auth/`, `lib/profile/` | Sign-in flows, Turnstile dialog, profile + avatar, `SubscriptionScreen`, `EntitlementService` |
| `lib/rooms/` | Lobby, room screen and its widgets, room models/service, dormancy & resume |
| `lib/sync/` | `SyncService` — the realtime sync engine (see `AGENTS.md` / `CLAUDE.md` for invariants) |
| `lib/av/` | LiveKit connection + track management |
| `lib/updates/` | Desktop self-update: appcast check + native updater handoff |
| `website/` | Next.js 15 marketing site, download portal, changelog, FAQ, auth & Paddle billing portal |
| `supabase/` | Migrations (schema/RLS/RPCs/cron), edge functions, auth config |

`AGENTS.md` and `CLAUDE.md` document the architecture and the sync-engine invariants in depth.

## Credits

Quick-reaction animations are [Noto Animated Emoji](https://googlefonts.github.io/noto-emoji-animation/)
by Google, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
They're bundled in `assets/emoji/` and refreshed by
`python3 tool/fetch_reaction_emoji.py`.
