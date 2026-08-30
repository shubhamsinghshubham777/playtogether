---
description: Realtime channel contracts, presence rate limits (5 calls / 30s), authority election, readiness gate lockstep, and YouTube IFrame intent model.
trigger: model_decision
---


# Sync Layer & Realtime Protocol

Guidance for working with `lib/sync/`, room state synchronization, and playback engines.

## 1. Sync Layer Architecture (`lib/sync/`)

`SyncService` is room-scoped: created on room entry with `(player, room, profile, role)`, disposed on leave. It broadcasts typed events (`sync_events.dart`): play/pause/seek, `state_request`/`state_response`, `mode_switch`, `chat`, `typing`, `position_sync` (host heartbeat every 10 s; members correct if drift > 1.5 s), `file_info` (local-file identity for mismatch banners), `room_ended`.

Two seams exist purely so the sync layer is testable via pure delegation:
- `lib/sync/sync_logic.dart`: Holds decisions as pure functions over plain values (authority election, gate evaluation, presence merge, last-action-wins ordering, reaction throttle, chat fuzzy-merge). `SyncService` delegates to it and re-exports it.
- `lib/sync/sync_backend.dart`: Narrows everything `SyncService` needs from Supabase and media_kit to one `SyncBackend` interface (plus `SyncChannel`/`SyncPlayer`), defaulted to real implementations. `SyncChannel` mirrors `RealtimeChannel`'s method shape.

### Echo & Loop Prevention
Three load-bearing mechanisms prevent feedback loops:
1. Channel `self: false`.
2. `_isApplyingRemoteAction` flag (reset after 100 ms settle window).
3. Last-action-wins timestamp ordering (`_shouldApply`).

### Late-Joiner State Sync
- Only the **authority** answers `state_request` (host if present, else earliest-joined present member) — computed with the *requester excluded*, so when the authority is the one asking (e.g. host reopening their own room), the next in line answers and there is always exactly one responder.
- Joiner retries once after 2 s then assumes idle.
- `_checkSelfGateSatisfaction` re-requests state on the edge where we *first* have the room's canonical media open. (The entry response is answered while the joiner still has the file picker open, so its seek hits an empty player and is lost).
- Resync is skipped when `_roomPlaying`/`_pausedByGate` (gate resume owns realignment) or when alone.

---

## 2. Presence & Rate Limiting (`TrailingThrottle`)

Presence is budgeted against the server's real contract: **5 calls per 30 seconds** (`CLIENT_PRESENCE_MAX_CALLS=5` over `CLIENT_PRESENCE_WINDOW_MS=30000`).
> [!WARNING]
> Realtime answers a client that tracks too fast with `Client presence rate limit exceeded` and drops the **whole channel** (sync, chat, readiness gate). It is a per-30-second budget, not a per-second rate.

`_presenceThrottle` has three essential parts:
1. **2 s coalescing interval**: Smooths bursts.
2. **Hard budget**: 4 calls per 30 s (one under server's 5 for safety margin).
3. **`presencePayloadsMatch` deduplication**: Opening dialogs churns readiness `none -> selecting -> none` (no net wire change); deduplication prevents burning the budget.
4. **Coalesces, never drops**: Presence *is* the gate; the last state must always flush.
5. **Resubscribes call `renew()`**: `renew()` waives spacing and drops dedupe memory because the new channel's presence is empty, but **keeps the budget**.
6. **`joined_at` fallback**: Must use cached timestamp, never a fresh `DateTime.now()`.

---

## 3. Dual-Player Routing & YouTube Bridge

`RoomScreen` sets `onRemotePlay/Pause/Seek` (+ `onRemoteDriftCorrect`, which must NOT pause YouTube) to route remote actions to the active player, and calls `updatePlaybackState(mode, youtubeUrl)` on mode changes.

### YouTube Bridge (`lib/player/youtube/`)
- Uses custom IFrame bridge running on a loopback `HttpServer` (`PTYouTubeController` via `flutter_inappwebview`). Never use inline HTML (Windows drops `InAppWebViewInitialData.baseUrl`).
- Windows requires `--autoplay-policy=no-user-gesture-required` on the WebView2 environment (`PTWebView.init`).
- `PTYouTubeEmbed` is a display surface only: wrap in `IgnorePointer` and keep `pointer-events: none` in the HTML page.

### YouTube Intent Model
- IFrame state transitions land 200–500 ms after commands (outside the 100 ms settle window).
- `_ytIntendedPlaying` in `RoomScreen` is the agreed play state: seeks restore it afterwards (`_ytSeekKeepingPlayState`).
- The player listener only broadcasts transitions that *diverge* from intended state.
- Remote commands arriving before the iframe is ready are queued and flushed on first ready tick.
- Changing videos **reuses the controller** (`loadVideo` → `cueVideoById`), keyed by `ObjectKey(controller)`, **never by URL**.

---

## 4. Readiness Gate (`lib/sync/` + `RoomScreen` + `readiness_overlay.dart`)

Nobody can start or scrub until **every present member** has the room's canonical media loaded.
- **Canonical media is room-level and host-only**: Written solely by `set_room_media` RPC. Clients refetch on entry and resubscribe. `RoomMedia.isNewerThan` (server clock `media_updated_at`) prevents clobbering by stale refetches.
- **Readiness rides on presence** (`ready_status`, `loaded_file_name`). `ReadyStatus` declaration order is its rank; multi-device merge keeps the most ready.
- **`gateState` is tri-state**: `indeterminate` until first presence sync—render as usable to avoid initial flashing.
- **Authority emits derived actions**: Gate play/pause uses `_roomPlaying` (room-level), not `isPlaying` (local player).
- **Gate actions carry `reason: 'gate'`** and never raise attribution toasts.
- **`waiveGateBlockers`**: Host-only waiver per member per media; clears when canonical media changes.
- **Gate at choke points**: Enforce in `_playPause`/`_seek`, not in individual UI widgets.
- **Kick/ban**: `member_kicked` broadcast is load-bearing because deleting `room_members` row does not auto-eject an open Realtime subscription.

---

## 5. Ephemeral Quick Reactions (`lib/rooms/reactions.dart`)

- **Ephemeral**: No DB row, no replay. Never touch playback machinery, never feed `remoteActions`.
- **Local echo**: Mandatory and unthrottled. Outgoing broadcasts capped at 1 per 250 ms (coalesced).
- **Receive side is tier-blind**: Allow-lists against `kAllReactions`. Send side enforces tier (`reactionAllowedForTier`).
- **Extended reactions fetched from CDN** (`lib/rooms/reaction_cdn.dart`) and SHA-256 verified against manifest.
- **Particle overlay**: Wrapped in `PTResponsive`, sits in a permanent `IgnorePointer`, shares one ticker capped at 14 particles.
