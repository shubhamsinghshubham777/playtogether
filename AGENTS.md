# SyncTogether Agent Guidelines

This repository is optimized for **Google Antigravity IDE** and intelligent pair programming agents.

---

## 1. Project Overview

SyncTogether is a cross-platform Flutter application for synchronized, low-latency media playback across devices.
- **Client**: Flutter (macOS, Windows, iOS, Android) using `media_kit` (local video) and an internal loopback IFrame bridge (YouTube).
- **Backend**: Supabase (PostgreSQL, Private Realtime channels, Row-Level Security, Edge Functions).
- **Audio/Video**: LiveKit for multi-participant voice & video facecam rails.
- **Billing & Web**: Next.js 15 marketing site and Paddle Merchant of Record billing portal in `website/`.

---

## 2. Essential Commands

> [!IMPORTANT]
> This project uses [FVM](https://fvm.app) to pin the Flutter SDK version. **Always prefix `flutter` and `dart` commands with `fvm`**.

```bash
# Full local dev ecosystem (Supabase, Edge Functions, Next.js Web)
./scripts/dev.sh                        # Spin up local stack
./scripts/dev.sh down                   # Cleanly spin down all services & free ports
./scripts/dev.sh status                 # Inspect status of all components

# Flutter Application
fvm flutter pub get                     # Install dependencies
fvm flutter run -d macos                # Run on macOS (or: windows, android, ios)
fvm dart format .                       # Auto-format all Dart code
fvm dart format --output=none --set-exit-if-changed . # Verify formatting matches CI
fvm flutter analyze                     # Static analysis (flutter_lints)
fvm flutter test                        # Run Dart unit/widget test suite

# Backend & Database
supabase start                          # Start local Supabase container stack
supabase db push                        # Apply migrations
supabase test db                        # Run pgTAP database test suite

# Web Application & Billing (website/)
cd website && npm run dev               # Run Next.js dev server (http://localhost:3000)
npm --prefix website test               # Run webhook idempotency & signature test suite
```

---

## 3. Core Development Conventions

1. **Exact Dependency Pins**: Dependencies in `pubspec.yaml` are exact pins (no `^` ranges). Keep them exact when adding or updating packages.
2. **Dot-Shorthand Syntax**: Use Dart dot-shorthand syntax for enum and static access (e.g. `mainAxisSize: .min`, `_mode = .local`).
3. **Design System & Tokens**:
   - Dark mode only (violet glass aesthetic).
   - Use tokens from `lib/ui/pt_theme.dart` (`PTColors`, `PTText`). Never hardcode raw hex values.
   - Use `PTLoader` (`lib/ui/loader.dart`), never `CircularProgressIndicator`.
4. **Error Handling vs. Analytics**:
   - **Diagnostics (`lib/diagnostics.dart`)**: Use `reportNonFatal` for unexpected caught errors and `trace(msg, category:, data:)` at state transitions. Never log per-tick or per-frame.
   - **Analytics (`lib/analytics.dart`)**: Use `Analytics.track` **only when an action was explicitly initiated by a human**. Never trigger analytics from background sync, remote actions, or gate evaluations.
5. **Generated Assets**: Never manually edit `assets/sfx/splash.wav`, `assets/emoji/*.json`, `assets/ca/cacert.pem`, or icon PNGs. Use the generator scripts in `tool/`.
6. **Licensing & Self-Hosting**: Licensed under PolyForm Noncommercial License 1.0.0 (`LICENSE`). Self-hosting documentation lives in `docs/self-hosting.md`. Commercial SaaS/resale and commercial use are restricted.
7. **Pre-Commit Verification & Cleanup (MANDATORY)**:
   Before committing code or concluding code modifications, the agent MUST ALWAYS run and verify the CI checks locally:
   - **Optimization & Cleanup**: Inspect `git status` and `git diff` for possible optimizations, redundant allocations, dead code, unused imports, or temporary scratch files, and clean them up without altering expected behavior.
   - **Format**: `fvm dart format --output=none --set-exit-if-changed .` (run `fvm dart format .` to format if differences exist).
   - **Analysis**: `fvm flutter analyze` (zero issues/warnings).
   - **Tests**: `fvm flutter test` (all unit and widget tests passing).
   - **Database**: `supabase test db` (mandatory whenever `supabase/` files are touched).
   Never commit or push code with unformatted files or failing tests.
8. **Communication & Formatting (MANDATORY)**:
   - **NEVER use LaTeX math formatting**: Never use LaTeX math syntax (such as `$`, `$$`, `\text{}`, `\frac{}`, `\times`, `\mathbf{}`, `\approx`, `\sim`, etc.) in chat responses, explanations, plans, walkthroughs, or markdown documents.
   - **Use clean plain text & standard symbols**: Always write out math using plain numbers, standard operators (`x`, `÷`, `=`, `~`, `approx`), percentages, and readable markdown tables so that calculations and breakdowns are crystal-clear and never show unrendered code clutter in any markdown viewer.

---

## 4. Modular Knowledge & Rules Index

Detailed domain-specific architecture and guidelines are split into progressive disclosure rules:

* **[Realtime & Sync Protocol](file:///.agents/rules/sync-and-realtime.md)**: Realtime channel contracts, presence rate limits (5 calls / 30s), authority election, readiness gate lockstep, YouTube IFrame intent model.
* **[Backend, Database & Entitlements](file:///.agents/rules/backend-and-entitlements.md)**: Supabase RLS policies, RPC invariants (`create_room`, `join_room`, `end_room`, `delete_room`), tier limits (`guest`/`free`/`premium`), Paddle webhook processing, and pgTAP testing.
* **[Auth, Security & Platform Specifics](file:///.agents/rules/auth-and-platform.md)**: Google OAuth PKCE deep linking, Cloudflare Turnstile loopback bridge, Windows WebView2 runtime, TLS root cert overrides, Sparkle/WinSparkle self-updates.
* **[UI Design System & Telemetry](file:///.agents/rules/ui-and-av.md)**: Glass rendering rules, LiveKit AV rails, diagnostics vs. analytics doctrines, and generated asset tools.

---

## 5. Skills & Slash Commands

Use the following workspace skills and slash commands:
- `/flutter-bump <version>`: Upgrades and synchronizes the pinned Flutter/Dart SDK across `.fvmrc`, `pubspec.yaml`, and CI workflows.
- `/release [version]`: Automates semantic version calculation, changelog generation, and installer build dispatch.
- **Skills Available**:
  - `dev-ecosystem`: Full local development stack management.
  - `test-pgtap`: Running and debugging SQL database tests.
  - `test-room-sync`: Testing two synchronized client instances locally.
  - `generate-assets`: Regenerating sound, emoji, certificate, and icon assets.
