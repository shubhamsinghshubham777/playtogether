<p align="center">
  <img src="assets/icon/app_icon.svg" width="96" alt="SyncTogether App Icon">
</p>

<h1 align="center">SyncTogether</h1>

<p align="center">
  <strong>Watch videos together, perfectly in sync. Cross-platform, low-latency, and self-hostable.</strong>
</p>

<p align="center">
  <a href="#license"><img src="https://img.shields.io/badge/License-BUSL--1.1-blue.svg" alt="License: BUSL-1.1"></a>
  <img src="https://img.shields.io/badge/Flutter-3.44.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Supabase-Realtime_%26_DB-3ECF8E?logo=supabase" alt="Supabase">
  <img src="https://img.shields.io/badge/LiveKit-AV_Mesh-FF5964?logo=webrtc" alt="LiveKit">
  <img src="https://img.shields.io/badge/Platforms-macOS_%7C_Windows_%7C_Android_%7C_iOS-blueviolet" alt="Platforms">
</p>

---

SyncTogether is a modern cross-platform application for synchronized media playback across devices. Create a **room**, share a 6-character room code (or a `synctogether://join/<code>` invite link), and keep everyone's playback in lockstep — play, pause, and seeks broadcast in real-time, accompanied by synchronized chat, animated emoji reactions, and live voice & video facecams.

## Preview

| Screen | Preview |
|---|---|
| **Splash** | <img src="https://github.com/user-attachments/assets/f6be89db-907d-4b2e-8553-87a2339f1e96" width="280" /> |
| **Lobby** | <img src="https://github.com/user-attachments/assets/cbd1b2ae-ba97-48ec-8636-dd2fc29b03a8" width="280" /> |
| **Room** | <img src="https://github.com/user-attachments/assets/520ddc80-dcb9-4588-a05e-9167e59ec2ca" width="280" /> |

---

## Key Features

- **Strict Lockstep Sync** — Millisecond-level synchronization with readiness gates, host drift-correction heartbeats, and authority-answered state recovery for late joiners.
- **Two Playback Modes** — Local video files (via `media_kit` hardware-accelerated rendering with file hash mismatch warnings) and YouTube (via internal loopback IFrame bridge).
- **Voice & Video Facecams** — Multi-participant live AV tiles powered by LiveKit SFU mesh with dynamic mic/camera controls.
- **Persisted Chat & Quick Reactions** — In-room chat history, typing indicators, and Google Noto animated emoji reactions.
- **Flexible Authentication** — Instant anonymous guest accounts (protected by Cloudflare Turnstile) or Google Sign-In with seamless in-place identity upgrades.
- **Resumable & Persistent Rooms** — Dormant rooms can be resumed by the host with playback position preserved, or extended/ended on demand.
- **Self-Hosting Ready** — Deploy the complete stack (Postgres database, Realtime engine, Edge Functions, LiveKit server, Web portal) on your own infrastructure or cloud free tiers.
- **Modern Violet Glass UI** — Consistent, dark glassmorphism design system across desktop, tablet, and mobile orientations.

---

## 🚀 Self-Hosting

SyncTogether is designed to be easily self-hosted. You can run it on your home server, local LAN, VPS, or private cloud.

> 📖 **Full Guide**: See [docs/self-hosting.md](docs/self-hosting.md) for detailed production deployment, Docker Compose recipes, and configuration options.

### Quick Start (Managed Hybrid Path)

1. **Deploy Supabase Backend**:
   - Create a free project at [database.new](https://database.new).
   - Push database migrations and RPCs:
     ```bash
     supabase login
     supabase link --project-ref <your-project-ref>
     supabase db push
     ```
2. **Deploy Edge Functions**:
   - Fill in `supabase/functions/.env` with your LiveKit API keys (from [cloud.livekit.io](https://cloud.livekit.io) or self-hosted server).
   - Deploy the token minter:
     ```bash
     supabase functions deploy livekit-token
     supabase secrets set --env-file supabase/functions/.env
     ```
3. **Build the Client**:
   - Copy `.env.example` to `.env` and fill in your `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `LIVEKIT_URL`.
   - Build for your platform:
     ```bash
     fvm flutter pub get
     fvm flutter run -d macos  # or windows, android, ios
     ```

### Self-Hosted LiveKit (Docker)

To self-host the LiveKit voice/video server on your own VPS or LAN:

```bash
# Start LiveKit SFU container
docker compose -f docker-compose.selfhost.yml up -d
```

---

## 🛠 Local Development Setup

SyncTogether includes an automated orchestrator script (`./scripts/dev.sh`) to spin up the local development stack (Supabase container stack, Edge Functions runtime, and Next.js web portal) with one command.

### Prerequisites

- [FVM](https://fvm.app) (Flutter Version Management)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`brew install supabase/tap/supabase`)
- [Docker Desktop](https://www.docker.com/) or OrbStack
- [Node.js](https://nodejs.org/) (v20+)

### Start Development Stack

```bash
# Spin up local Supabase, Edge Functions, and Next.js web portal
./scripts/dev.sh

# Run the Flutter desktop app (Instance A)
fvm flutter run -d macos

# Run an isolated second client for room testing (Instance B)
./build/pt-instance-b.sh

# Check ecosystem health
./scripts/dev.sh status

# Spin down all services and clean up ports
./scripts/dev.sh down
```

---

## 🧪 Testing & Code Quality

SyncTogether maintains comprehensive test coverage across client, database, and web layers:

```bash
# 1. Run Flutter unit & widget tests
fvm flutter test

# 2. Run Supabase pgTAP database RPC & RLS tests
supabase start && supabase test db

# 3. Run Web application & billing webhook tests
npm --prefix website test

# 4. Run static analysis
fvm flutter analyze
```

---

## 📦 Installers & Desktop Self-Updates

Release builds and installer artifacts are built via GitHub Actions (`.github/workflows/`):
- **macOS**: DMG package with Sparkle-based auto-updater.
- **Windows**: Inno Setup installer (`dart run inno_bundle`) with WinSparkle auto-updater and `synctogether://` protocol registration.
- **Android**: Release APK.

---

## 📂 Repository Layout

| Directory | Description |
|---|---|
| `lib/ui/` | Violet glass design system: tokens (`PTColors`, `PTText`), buttons, inputs, loaders (`PTLoader`), dialogs |
| `lib/auth/`, `lib/profile/` | Authentication flows, Turnstile captcha bridge, user profiles, entitlement management |
| `lib/rooms/` | Lobby, room screen, participant grid, dormancy/resume engine, room service |
| `lib/sync/` | Lockstep synchronization engine (`SyncService`, `SyncBackend`, `SyncLogic`) |
| `lib/av/` | LiveKit SFU audio/video connection & facecam tiles |
| `lib/updates/` | Desktop self-update service (Sparkle / WinSparkle appcast parser) |
| `docs/` | In-depth technical documentation & [Self-Hosting Guide](docs/self-hosting.md) |
| `docker/` | Docker Compose and server configuration templates for self-hosting |
| `supabase/` | Database migrations (schema, RLS, RPCs, pg_cron), edge functions, auth config |
| `website/` | Next.js 15 marketing site, download portal, changelog, FAQ, and Paddle billing |
| `tool/` | Asset generation scripts (audio, emoji, certificates, app icons) |

---

## 📄 License & Business Notice

SyncTogether is licensed under the **[Business Source License 1.1 (BUSL-1.1)](LICENSE)**.

### What is permitted:
- ✅ **Self-Hosting**: You are 100% free to self-host, run, inspect, and modify SyncTogether for personal, educational, family, community, or internal organizational use.
- ✅ **Contributions & Forking**: You can fork the repository, build custom features, submit pull requests, and deploy private instances.

### What is prohibited:
- ❌ **Commercial Resale / SaaS**: You may **not** sell SyncTogether as your own product, package it into a commercial distribution, or offer it as a paid commercial hosted service / SaaS to third parties without an explicit commercial license from the Licensor.

*After a 4-year period from release, the license automatically transitions to the permissive **Apache License, Version 2.0**.*

---

## 👏 Credits & Third-Party Assets

- **Animated Reactions**: [Noto Animated Emoji](https://googlefonts.github.io/noto-emoji-animation/) by Google (licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)).
- **Video Playback**: [media_kit](https://github.com/media-kit/media-kit) (MPV-backed high performance player for Flutter).
- **WebRTC Mesh**: [LiveKit](https://livekit.io) real-time video and audio platform.
