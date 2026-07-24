# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PlayTogether is a Flutter app for synchronized ("watch together") media playback across devices. Two peers join a shared Supabase Realtime channel; play/pause/seek/mode changes on one client are broadcast to the other. It supports two playback modes: **local** files (via media_kit) and **YouTube** videos (via youtube_player_flutter). It also has an in-app chat with typing indicators and presence.

## Setup & Commands

This project uses [fvm](https://fvm.app) to manage the Flutter SDK version — **always prefix `flutter` and `dart` commands with `fvm`** (e.g. `fvm flutter run`, `fvm dart run inno_bundle`).

A `.env` file must exist in the repo root before running or building — it is declared as a Flutter asset, so `flutter build`/`run` fail without it. Copy `.env.example` and fill in `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (real values linked in README.md).

```bash
fvm flutter pub get                 # install dependencies
fvm flutter run -d macos            # run (or: windows, linux, android, ios)
fvm flutter analyze                 # lint (flutter_lints via analysis_options.yaml)
fvm flutter build macos --release   # release build per platform
```

There are no tests (no `test/` directory). CI (`.github/workflows/`) is manual-trigger only (`workflow_dispatch`) and builds installers: Windows via `dart run inno_bundle` + Inno Setup (configured in pubspec.yaml under `inno_bundle:`), macOS via DMG. CI uses Flutter 3.38.1 and writes `.env` from the `ENV_FILE` secret.

## Conventions

- Dependency versions in pubspec.yaml are **exact pins** (no `^` ranges) — keep it that way when adding/updating dependencies.
- The code uses Dart's dot-shorthand syntax for enum/static access (e.g. `mainAxisSize: .min`, `_currentMode = .local`, `FlexThemeData.dark(scheme: .cyanM3)`) — requires the pinned SDK (3.12.2); follow this style.
- App version lives in pubspec.yaml `version:`; CI extracts it for installer names.

## Architecture

Startup flow (`lib/main.dart`): username dialog → creates `SyncService` (connects to Supabase) → renders `PTVideoPlayer`. The media_kit `Player` is created once in `MainApp` and passed down.

### Sync layer (`lib/sync/`)

`SyncService` is the heart of the app. It wraps a single hardcoded Supabase Realtime channel (`playtogether:default`) — there are no rooms; everyone shares one channel. It:

- Broadcasts and handles typed events defined in `sync_events.dart` (`play`, `pause`, `seek`, `state_request`/`state_response`, `mode_switch`, `chat`, `typing`), each carrying `senderId` + `timestamp`.
- Exposes broadcast `Stream`s (chat, typing, peer presence, mode switch) that UI widgets subscribe to.
- **Echo/loop prevention** — three mechanisms work together:
  - channel is created with `self: false` so a client never receives its own broadcasts;
  - `_isApplyingRemoteAction` flag suppresses re-broadcasting while a remote action is being applied (reset after a 100ms settle delay);
  - last-action-wins: incoming events with `timestamp <= _lastAppliedTimestamp` are dropped (`_shouldApply`).
- **Late-joiner state sync**: on subscribe, a client sends `state_request`; any peer with media loaded replies with `state_response` (playing/position/mode/YouTube URL); only the first response is applied.
- **Dual-player routing**: `SyncService` doesn't know about YouTube. `PTVideoPlayer` sets `onRemotePlay`/`onRemotePause`/`onRemoteSeek` callbacks that route remote actions to whichever player is active; if unset, `SyncService` falls back to controlling the media_kit `Player` directly. `PTVideoPlayer` must call `updatePlaybackState(mode, youtubeUrl)` on mode changes so state responses are accurate.

### Player layer (`lib/player/`)

`PTVideoPlayer` owns mode state (`PlaybackMode.local` / `.youtube`) and swaps between the media_kit `Video` widget and `yt.YoutubePlayer` in a `Stack`. Local mode uses custom controls (`_PTVideoPlayerControls`, in the same file) with keyboard shortcuts (space/K play-pause, J/L/arrows seek, arrows volume); YouTube mode overlays `YouTubeControls`. Every user-initiated play/pause/seek must both act on the local player *and* call the matching `syncService.broadcast*` method — play/pause also broadcast a seek to keep positions aligned. YouTube play/pause state changes are additionally detected via a controller listener (`_onYouTubePlayerEvent`) since the embedded player has its own UI.

Dialog handling around mode switches is delicate: remote `mode_switch` events must dismiss any locally open mode-selection/URL dialogs (tracked with `_isModeSelectionDialogOpen` / `_isYouTubeUrlDialogOpen` flags) before applying the switch.

### Chat (`lib/chat/`)

`ChatBox` slides in as a side panel; unread count badges accumulate while closed. History is kept in-memory in `SyncService` (no persistence).
