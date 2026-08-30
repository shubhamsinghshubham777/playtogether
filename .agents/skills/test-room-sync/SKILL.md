---
name: test-room-sync
description: >-
  Run dual macOS client instances to test synchronized media playback, room chat, reactions, and readiness gating on a single machine. Use when the user asks to "test sync locally", "run two instances", "test multi-client playback", or execute `./build/pt-instance-b.sh`.
---

# Dual-Instance Room Sync Testing

Testing real-time synchronization between two participants on a single Mac requires two distinct app identities with separated preference domains (`NSUserDefaults` and `flutter_secure_storage`).

## Steps to Test

1. **Build & Run Instance A (Host)**:
   ```bash
   fvm flutter run -d macos
   ```
   Sign in (or join as Guest) and create a room.

2. **Launch Instance B (Participant)**:
   In a separate terminal:
   ```bash
   ./build/pt-instance-b.sh
   ```
   This script clones the debug `.app` bundle under a secondary bundle ID (`app.synctogether.macos.b`) to ensure an isolated Supabase session.

3. **Verify Sync Interactions**:
   - Copy the 6-character room code or invite URL from Instance A and join from Instance B.
   - Test Play, Pause, Scrubbing, Readiness Gate overlays, and Quick Reactions.
   - Inspect Instance B logs at `/tmp/pt-b.log`.

> [!NOTE]
> Whenever you recompile the Flutter app, re-run `./build/pt-instance-b.sh` so Instance B receives the new binary.
