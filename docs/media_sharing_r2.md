# Media Sharing via Cloudflare R2

Host-initiated, per-room file sharing that lets a premium host upload their local media file to Cloudflare R2, making it downloadable by every member in the room. The file is stored temporarily, deleted on room retirement or when the host toggles sharing off, and the entire lifecycle integrates with the existing gate, presence, tier, and sync systems.

## User Review Required

> [!IMPORTANT]
> **Free-tier bandwidth tracking lives in the database, not on the client.** The Edge Function that issues presigned upload URLs checks `profiles.r2_upload_bytes_7d` and rejects uploads that would exceed 4 GB / 7 days. This means the limit is un-bypassable (same doctrine as every other tier cap), but it also means the free-tier column and the rolling-window logic are new schema.

> [!IMPORTANT]
> **Cloudflare R2 credentials are server-side secrets.** `CF_R2_ACCOUNT_ID`, `CF_R2_ACCESS_KEY_ID`, `CF_R2_SECRET_ACCESS_KEY`, and `CF_R2_BUCKET_NAME` live in `supabase/functions/.env` (never in the client `.env`). The client never sees R2 credentials — it only receives presigned URLs from Edge Functions.

> [!WARNING]
> **Pre-upload disk space check on members is best-effort.** On macOS/Windows/Linux, `dart:io` can query free disk space reliably. On Android/iOS, sandbox restrictions make the query approximate. The opt-in dialog ("This file is 4.3 GB — download it?") is the real gate; the programmatic check is a courtesy to skip members who clearly can't fit it. If the OS query fails, the member still gets the dialog.

> [!WARNING]
> **The file-switch lock is a UX trade-off.** While the download toggle is on, the host cannot switch to a different local file — they must toggle off first (which deletes the R2 object and triggers a confirmation dialog). This avoids partial-download orphans and re-upload races, but it means the host has to go through two dialogs to change movies.

## Resolved Decisions

All open questions have been answered. Summary of decisions:

| Decision | Resolution |
|---|---|
| **R2 bucket provisioning** | Manual one-time creation via Cloudflare dashboard. A setup guide is included below. |
| **Upload dependencies** | Use `minio` (S3-compatible Dart SDK) for multipart upload with resume. Simpler code over zero deps. |
| **Download resume** | HTTP `Range`-based resume on all platforms. Partial files persisted to disk. |
| **Free-tier bandwidth tracking** | Server-side in database (accepted). |
| **Disk space check** | Best-effort programmatic + opt-in dialog as real gate (accepted). |
| **R2 credentials** | Server-side secrets only (accepted). |

---

## Prerequisite: Cloudflare R2 Setup Guide

Cloudflare R2 is a **separate service** from Supabase Storage. Supabase's free-tier storage (1 GB storage, 2 GB bandwidth/month) is insufficient for video files. R2's free tier provides **10 GB storage** and **$0.00 egress** (unlimited download bandwidth), which is why this plan uses it.

### One-time setup steps:

1. **Create a Cloudflare account** (free) at [dash.cloudflare.com](https://dash.cloudflare.com).

2. **Enable R2** in the Cloudflare dashboard:
   - Navigate to **R2 Object Storage** in the left sidebar.
   - Accept the R2 terms (no credit card required for free tier usage under 10 GB storage + 10M Class B requests/month).

3. **Create the bucket**:
   - Click **Create bucket**.
   - Name: `playtogether-media` (or your preference).
   - Location hint: **Automatic** (Cloudflare picks the nearest region to your users).
   - Default storage class: **Standard**.

4. **Set up a lifecycle rule** (safety net for orphaned files):
   - Go to the bucket → **Settings** → **Object lifecycle rules**.
   - Add rule: **Delete objects** older than **48 hours**.
   - This is a safety net — the database-driven cleanup should delete files much sooner.

5. **Create an API token** for the Edge Functions:
   - Go to **R2 Object Storage** → **Manage R2 API tokens** → **Create API token**.
   - Permissions: **Object Read & Write** on the `playtogether-media` bucket only.
   - Copy the **Access Key ID** and **Secret Access Key**.

6. **Note your Account ID**:
   - Visible in the Cloudflare dashboard URL: `dash.cloudflare.com/<account-id>/...`
   - Or: **Overview** page → right sidebar → **Account ID**.

7. **Add credentials to Edge Functions**:
   ```bash
   # In supabase/functions/.env, add:
   CF_R2_ACCOUNT_ID=<your-account-id>
   CF_R2_ACCESS_KEY_ID=<from-step-5>
   CF_R2_SECRET_ACCESS_KEY=<from-step-5>
   CF_R2_BUCKET_NAME=playtogether-media
   # R2's S3-compatible endpoint (derived from account ID):
   CF_R2_ENDPOINT=https://<your-account-id>.r2.cloudflarestorage.com
   ```

8. **Deploy the secrets**:
   ```bash
   supabase secrets set --env-file supabase/functions/.env
   ```

### R2 Free Tier Limits (as of 2026):
| Resource | Free Allowance | Overage |
|---|---|---|
| Storage | 10 GB / month | $0.015 / GB-month |
| Class A ops (PUT, POST, LIST) | 1,000,000 / month | $4.50 / million |
| Class B ops (GET, HEAD) | 10,000,000 / month | $0.36 / million |
| **Egress (downloads)** | **Unlimited — $0.00 forever** | N/A |

---

## Proposed Changes

### 1. Database Schema — New Migration

#### [NEW] `supabase/migrations/YYYYMMDDHHMMSS_media_sharing.sql`

Adds the columns and RPCs needed for media sharing state, free-tier bandwidth tracking, and cleanup.

**Schema changes on `rooms`:**
```sql
alter table public.rooms
  add column media_download_url text           -- presigned R2 download URL (null = sharing off)
    check (char_length(media_download_url) between 1 and 2048),
  add column media_file_size bigint            -- bytes, for disk-space checks and progress UI
    check (media_file_size > 0),
  add column media_r2_key text                 -- R2 object key, for server-side deletion
    check (char_length(media_r2_key) between 1 and 512),
  add column media_upload_state text not null default 'none'
    check (media_upload_state in ('none', 'uploading', 'ready', 'failed'));
```

**Schema changes on `profiles` (free-tier bandwidth tracking):**
```sql
alter table public.profiles
  add column r2_upload_bytes_7d bigint not null default 0,
  add column r2_upload_window_start timestamptz not null default now();
```

**Schema changes on `tier_limits`:**
```sql
alter table public.tier_limits
  add column media_sharing text not null default 'none'
    check (media_sharing in ('none', 'limited', 'full')),
  add column media_sharing_weekly_bytes bigint not null default 0;
```

Seeded values:
| Tier | `media_sharing` | `media_sharing_weekly_bytes` |
|---|---|---|
| guest | `none` | 0 |
| free | `limited` | 4,294,967,296 (4 GB) |
| premium | `full` | 0 (unlimited) |

**New column on `rooms` from `create_room` denormalization:**
```sql
-- In create_room, add to the INSERT:
media_sharing_level = v_limits.media_sharing
```

This follows the existing pattern: the room owns its properties, not the joiner. A free user joining a premium host's room gets `media_sharing = 'full'` because it was stamped from the host's tier at creation time.

**New RPCs:**

1. `set_media_upload_state(p_room_id, p_state, p_download_url, p_file_size, p_r2_key)` — Host only. Sets the upload lifecycle columns on the room row. Called by the Edge Function after presigned URL generation and by the client on upload completion/failure.

2. `clear_media_sharing(p_room_id)` — Host only. Nulls the download/R2 columns and resets `media_upload_state` to `'none'`. Called when the host toggles sharing off.

3. `record_upload_bytes(p_user_id, p_bytes)` — `security definer`. Adds bytes to the user's rolling window. Called by the Edge Function after issuing a presigned upload URL. If `r2_upload_window_start` is older than 7 days, resets the counter first.

**Cleanup integration in `retire_room`:**
- When `retire_room` runs, if `media_r2_key` is not null, it sets a flag (or inserts into a new `pending_r2_deletions` table) that the cleanup cron reads. The actual R2 deletion happens via an Edge Function called by `pg_cron` or a separate scheduled Edge Function, because Postgres cannot make HTTP calls to Cloudflare directly.

**`pending_r2_deletions` table:**
```sql
create table public.pending_r2_deletions (
  id bigint generated always as identity primary key,
  r2_key text not null,
  created_at timestamptz not null default now()
);
```

`retire_room` inserts into this table before nulling the room's R2 columns. A scheduled Edge Function (`cleanup-r2`) polls this table every 5 minutes, deletes the R2 objects, and removes the rows.

---

### 2. Supabase Edge Functions

#### [NEW] `supabase/functions/media-upload-url/index.ts`

Mints a presigned S3-compatible PUT URL for the host to upload directly to R2. Guards:
- Caller must be authenticated and host of a live room.
- Room's `media_sharing_level` must be `'limited'` or `'full'`.
- If `'limited'`, check `profiles.r2_upload_bytes_7d` against `tier_limits.media_sharing_weekly_bytes`. Reject if exceeded.
- File size (passed as param) must be ≤ 10 GB.
- Generates a unique R2 key: `rooms/{room_id}/{uuid}.{extension}`.
- Uses the AWS S3 SDK (`@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`) to generate the presigned PUT URL (1-hour expiry for the upload, long-lived GET URL or separate presigned GET).
- Calls `set_media_upload_state(room_id, 'uploading', download_url, file_size, r2_key)`.
- If `'limited'`, calls `record_upload_bytes(user_id, file_size)` to debit the quota.
- Returns `{ uploadUrl, downloadUrl, r2Key, expiresIn }`.

**For multipart uploads** (files > 100 MB):
- The Edge Function initiates the multipart upload, returns the `uploadId` + presigned URLs for each part.
- OR: simpler approach — a single presigned PUT URL works for files up to 5 GB on R2. For files > 5 GB, the Edge Function returns multiple part-presigned URLs. The client assembles them.

#### [NEW] `supabase/functions/cleanup-r2/index.ts`

Scheduled Edge Function (called by `pg_cron` every 5 minutes via `net.http_post` or a Supabase Cron Job):
- Reads all rows from `pending_r2_deletions`.
- Deletes corresponding R2 objects via `DeleteObjectCommand`.
- Removes processed rows from `pending_r2_deletions`.
- Also sweeps R2 objects whose room's `media_upload_state` is `'uploading'` for longer than 2 hours (abandoned uploads).

#### [MODIFY] `supabase/functions/.env.example`

Add:
```
CF_R2_ACCOUNT_ID=
CF_R2_ACCESS_KEY_ID=
CF_R2_SECRET_ACCESS_KEY=
CF_R2_BUCKET_NAME=
CF_R2_PUBLIC_URL=
```

---

### 3. Client-Side Dart — New Service

#### [NEW] `lib/rooms/media_sharing_service.dart`

The core orchestrator for the upload/download lifecycle. Singleton, like other services.

**Responsibilities:**
- **Upload** (host): Picks up the presigned URL from the Edge Function, performs chunked HTTP PUT (with retry per chunk), tracks progress, broadcasts progress via Supabase Realtime every 5% (or on speed/ETA change).
- **Download** (member): HTTP GET with `Range` header support for resume. Saves to app support directory. Tracks progress. Broadcasts download-complete status via presence.
- **Lifecycle**: Cancel upload/download, clean up partial files, manage disk space.

**Key state:**
```dart
enum MediaSharingState { none, requesting, uploading, ready, failed }

class MediaSharingProgress {
  final double fraction;     // 0.0–1.0
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSec;
  final Duration eta;
}
```

**Upload flow (host):**
1. `startUpload(roomId, filePath, fileName, fileSize)`:
   - Calls `media-upload-url` Edge Function → gets presigned PUT URL.
   - Opens file as a stream, uploads in 5 MB chunks.
   - Every 5% progress (or every 10 seconds, whichever is less frequent), broadcasts `upload_progress` event via Realtime.
   - On completion, calls `set_media_upload_state(room_id, 'ready', ...)` RPC.
   - On failure (after retries), calls `set_media_upload_state(room_id, 'failed', ...)`.

2. `cancelUpload()`:
   - Cancels the HTTP client.
   - Calls `clear_media_sharing(room_id)` RPC.
   - Queues R2 deletion via `pending_r2_deletions`.

**Download flow (member):**
1. `startDownload(roomId, downloadUrl, fileName, fileSize)`:
   - Checks available disk space (best-effort).
   - Opens HTTP GET with `Range` header if partial file exists.
   - Streams to `getApplicationSupportDirectory()/pt_downloads/{room_id}/{fileName}`.
   - Updates presence with download progress (every 5%).
   - On completion, registers file with `LocalMediaStore` and auto-opens in player.

2. `cancelDownload()`:
   - Cancels the HTTP client.
   - Deletes partial file.

**Retry logic:**
- Upload: Retry each 5 MB chunk up to 3 times with exponential backoff (1s, 2s, 4s). If a chunk fails 3 times, mark upload as `failed`.
- Download: Retry with Range resume up to 5 times. On persistent failure, show a "Retry download" button.

**Network loss handling:**
- Listen to connectivity changes. On reconnect, auto-resume the upload/download from the last successful chunk/byte offset.

#### [NEW] `lib/rooms/media_sharing_cache.dart`

Manages the on-disk cache of downloaded media files.

**Responsibilities:**
- Store files in `getApplicationSupportDirectory()/pt_downloads/{room_id}/`.
- Track files via `shared_preferences` (similar to `LocalMediaStore`):
  ```json
  {
    "room_abc": { "name": "Movie.mkv", "path": "/path/to/file", "size": 1234567, "downloaded_at": 1234567890 }
  }
  ```
- **Cleanup rules:**
  - On app start: delete files whose room is no longer in `list_my_rooms()` (room ended/expired/left).
  - On app start: delete files older than 7 days regardless.
  - When host toggles sharing off: delete the file for that room on all members (broadcast triggers this).
  - Integrate with `LocalMediaStore.prune()` so both stores are pruned together.

---

### 4. Client-Side Dart — Sync Layer Changes

#### [MODIFY] [sync_events.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/sync/sync_events.dart)

Add new event types:
```dart
static const String uploadProgress = 'upload_progress';
static const String downloadOptIn = 'download_opt_in';
static const String sharingToggled = 'sharing_toggled';
static const String diskSpaceCheck = 'disk_space_check';
static const String diskSpaceResult = 'disk_space_result';
```

New event classes:
- `UploadProgressEvent` — `{ fraction, speedBps, etaSeconds, state }` — broadcast by host every 5%.
- `SharingToggledEvent` — `{ enabled, downloadUrl, fileName, fileSize, r2Key }` — broadcast by host on toggle.
- `DiskSpaceCheckEvent` — `{ fileName, fileSize }` — broadcast by host before upload starts, requesting members to report their space.
- `DiskSpaceResultEvent` — `{ hasSpace, availableBytes, optedIn }` — each member responds.

#### [MODIFY] [sync_service.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/sync/sync_service.dart)

Add handlers and broadcast methods for the new events:
- `broadcastUploadProgress(...)` — host only, throttled to every 5%.
- `broadcastSharingToggled(...)` — host only.
- `broadcastDiskSpaceCheck(...)` — host only, before upload.
- `broadcastDiskSpaceResult(...)` — each member responds.
- Corresponding stream controllers and `_guard`-wrapped handlers.

---

### 5. Client-Side Dart — Entitlement Changes

#### [MODIFY] [entitlement_service.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/profile/entitlement_service.dart)

Add to `TierLimits`:
```dart
final String mediaSharing;       // 'none', 'limited', 'full'
final int mediaSharingWeeklyBytes; // 0 = unlimited (premium)
```

Add convenience getters:
```dart
bool get canShareMedia => mediaSharing != 'none';
bool get hasUnlimitedSharing => mediaSharing == 'full';
```

---

### 6. Client-Side Dart — Room Model Changes

#### [MODIFY] [room_models.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/rooms/room_models.dart)

Add to `Room`:
```dart
final String? mediaDownloadUrl;
final int? mediaFileSize;
final String? mediaR2Key;
final String mediaUploadState; // 'none', 'uploading', 'ready', 'failed'
final String mediaSharingLevel; // 'none', 'limited', 'full' — denormalized from host's tier
```

Update `Room.fromJson` to parse these fields.

---

### 7. Client-Side Dart — Room Screen UI Changes

#### [MODIFY] [room_screen.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/rooms/room_screen.dart)

This is the largest UI change. Organized by concern:

**A. New state variables:**
```dart
MediaSharingState _sharingState = .none;
MediaSharingProgress? _uploadProgress;
MediaSharingProgress? _downloadProgress;
bool _sharingToggle = false;          // host's toggle state
bool _downloadOptInShown = false;     // member has seen the opt-in dialog
bool _downloadOptedIn = false;        // member accepted
List<(String userId, bool hasSpace, bool optedIn)> _memberDiskResults = [];
```

**B. Host flow — toggle in topbar:**

1. **Toggle visibility**: Only shown when:
   - `_mode == .local` AND a file is loaded (i.e., `_localFileName != null`)
   - Room's `mediaSharingLevel` is not `'none'` (room was created by a premium or free-with-quota host)
   - User is the host

2. **Toggle ON (host taps it):**
   - Show confirmation dialog: "Share this file with room members? This will upload `{fileName}` ({formattedSize}) to the cloud so everyone can download it."
   - If `mediaSharingLevel == 'limited'`: show remaining weekly quota in the dialog.
   - If confirmed:
     a. Broadcast `disk_space_check` with `{ fileName, fileSize }`.
     b. Wait for all present members to respond (with a 15-second timeout, after which non-respondents are treated as "not ready").
     c. Show results in a dialog similar to the existing gate readiness overlay: "Member X: ✓ Ready (12 GB free)" / "Member Y: ✗ Not enough space (800 MB free)" / "Member Z: Declined".
     d. Host decides: proceed (skipping non-ready members via existing gate waiver) or cancel.
     e. If proceeding: call `media-upload-url` Edge Function, start upload.
     f. Broadcast `sharing_toggled { enabled: true, ... }`.

3. **Toggle OFF (host taps it while sharing is active):**
   - Show confirmation dialog: "Stop sharing? The uploaded file will be deleted from the cloud, and members who haven't finished downloading will lose their progress."
   - If confirmed:
     a. Cancel any in-progress upload.
     b. Call `clear_media_sharing(room_id)` RPC.
     c. Broadcast `sharing_toggled { enabled: false }`.
     d. Queue R2 deletion.

4. **File switch blocked while toggle is on:**
   - `_pickVideo()` checks `_sharingToggle`. If on, shows a snackbar/tooltip: "Turn off file sharing first to switch files."
   - `_handleSwitchSource()` similarly blocked with explanation.

**C. Host flow — upload progress:**
- While uploading, the topbar shows a determinate progress bar with speed and ETA.
- Every 5% progress, `broadcastUploadProgress(...)` is called.
- Upload completion: snack "File is ready — members can now download it." + broadcast `upload_progress { state: 'ready' }`.
- Upload failure: snack "Upload failed — try again?" with retry button.

**D. Member flow — opt-in dialog:**
- On receiving `sharing_toggled { enabled: true }`:
  1. Show a dialog: "**{hostName}** is sharing `{fileName}` ({formattedSize}). Download it when the upload finishes?"
     - **"Download"** → set `_downloadOptedIn = true`, update presence, wait for upload to complete, auto-start download.
     - **"Leave room"** → call `_leaveRoom()`.
  2. The dialog also shows: "Available space: {freeSpace}" (best-effort).
  3. If insufficient space: dialog says "You don't have enough space ({freeSpace} free, {fileSize} needed). Free up space and come back, or leave the room." with a "Open Settings" CTA (launches system storage settings) and a "Check again" button that re-queries disk space.

- On receiving `disk_space_check`:
  1. Query available disk space.
  2. Respond with `disk_space_result { hasSpace, availableBytes }`.
  3. The opt-in dialog is what actually decides `optedIn`.

**E. Member flow — download progress:**
- After upload completes (receives `upload_progress { state: 'ready' }`) and member opted in:
  1. Auto-start download from `mediaDownloadUrl`.
  2. Show progress in the gate readiness overlay area (or a dedicated progress indicator).
  3. On completion:
     - Register with `LocalMediaStore`.
     - Auto-open in player: `widget.player.open(Media(downloadedFilePath))`.
     - Update readiness status to `ready`.
     - Gate opens automatically.
  4. On failure: "Download failed" with retry button.

**F. Member flow — during upload (before download):**
- Members see the host's upload progress (received via `upload_progress` broadcasts).
- The gate overlay says: "{hostName} is uploading `{fileName}`… ({progress}%, ~{eta} remaining)"
- Members can chat, voice call, or switch to YouTube in the meantime (the host controls the mode switch, and the download is unaffected by mode changes).

**G. Late joiner flow:**
- When a member joins a room where `media_upload_state == 'ready'` and `media_download_url` is set:
  1. Show the same opt-in dialog as above.
  2. If accepted, start download immediately.

**H. Tier gating UI:**
- If the room's `mediaSharingLevel` is `'none'` (guest-hosted room), the toggle is hidden entirely.
- If the **host's own tier** is `'guest'` and they try to access sharing: show `PremiumTeaseDialog` with sign-in CTA (following existing guest upsell pattern).
- If the **host's own tier** is `'free'` and they've exceeded the 4 GB weekly quota: show a dialog "You've used your free sharing quota this week ({used}/{limit}). Go premium for unlimited sharing." with the standard premium tease.
- Remember: the room's `mediaSharingLevel` is denormalized from the host's tier at creation. A free user in a premium room sees `mediaSharingLevel = 'full'` on the room, but the toggle is host-only so they can't trigger it anyway.

---

### 8. UI Widgets

#### [NEW] `lib/rooms/widgets/media_sharing_toggle.dart`

A toggle widget for the room topbar. Shows:
- Off state: cloud-upload icon with "Share file" tooltip.
- Uploading state: animated cloud-upload icon with circular progress.
- Ready state: cloud-done icon with "Sharing on" label, tappable to toggle off.
- Failed state: cloud-error icon with "Retry" tooltip.

Uses the existing `PTIconButton` and design tokens from `PTColors`/`PTText`.

#### [NEW] `lib/rooms/widgets/download_opt_in_dialog.dart`

Glass dialog shown to members when the host enables sharing:
- File name, file size, available disk space.
- "Download" / "Leave room" CTAs (following existing dialog patterns).
- Insufficient-space variant with "Open Settings" + "Check again" CTAs.

#### [NEW] `lib/rooms/widgets/sharing_progress_indicator.dart`

Compact progress indicator for both upload (host's topbar) and download (member's gate overlay):
- Determinate progress bar.
- Speed (formatted: "12.4 MB/s") and ETA ("~2 min left").
- Cancel button.

#### [MODIFY] `lib/rooms/widgets/extend_room_dialog.dart` (PremiumTeaseDialog)

Add "File sharing" to the premium perks list where appropriate:
```dart
'Share local files with room members',
```

---

### 9. Analytics Events

Following the existing analytics doctrine ("a product event may fire **only where a human caused it**"):

| Event | Properties | Fires when |
|---|---|---|
| `media_sharing_toggled` | `room_id`, `enabled`, `file_size`, `tier` | Host toggles sharing on/off |
| `media_upload_started` | `room_id`, `file_size` | Upload begins |
| `media_upload_completed` | `room_id`, `file_size`, `duration_seconds` | Upload finishes successfully |
| `media_upload_failed` | `room_id`, `file_size`, `error` | Upload fails after retries |
| `media_upload_cancelled` | `room_id`, `bytes_uploaded` | Host cancels upload |
| `media_download_opted_in` | `room_id`, `file_size` | Member accepts download dialog |
| `media_download_opted_out` | `room_id`, `reason` (`'declined'` / `'no_space'`) | Member declines |
| `media_download_completed` | `room_id`, `file_size`, `duration_seconds` | Member download completes |
| `media_download_failed` | `room_id`, `file_size`, `error` | Member download fails |
| `media_sharing_quota_hit` | `used_bytes`, `limit_bytes` | Free-tier host hits weekly limit |

---

### 10. Diagnostics & Instrumentation

Following the existing instrumentation doctrine:

**`trace` breadcrumbs** (category: `media`):
- `'media sharing toggled'` — `{ room_id, enabled, file_size }`
- `'upload chunk completed'` — `{ chunk, totalChunks, bytesUploaded }` (only on retry, not every chunk)
- `'download started'` — `{ room_id, file_size, resumed: bool }`
- `'download chunk retry'` — `{ attempt, offset }`
- `'r2 cleanup queued'` — `{ r2_key, room_id }`

**`reportNonFatal`** in all `catch` blocks:
- Edge Function call failures.
- Upload/download HTTP errors (after retry exhaustion).
- Disk space query failures.
- R2 presigned URL generation failures.

---

### 11. Environment & CI Changes

#### [MODIFY] [.env.example](file:///Users/shubham/Projects/Personal/playtogether/.env.example)

No changes needed — R2 credentials are server-side only.

#### [MODIFY] [supabase/functions/.env.example](file:///Users/shubham/Projects/Personal/playtogether/supabase/functions/.env.example)

Add:
```
CF_R2_ACCOUNT_ID=
CF_R2_ACCESS_KEY_ID=
CF_R2_SECRET_ACCESS_KEY=
CF_R2_BUCKET_NAME=
CF_R2_PUBLIC_URL=
```

#### [MODIFY] CI workflows

Add `supabase functions deploy media-upload-url` and `supabase functions deploy cleanup-r2` to deployment steps. Add R2 secrets to the Supabase secrets set command.

---

### 12. Edge Cases & Production Hardening

| Edge Case | Handling |
|---|---|
| **Host leaves room mid-upload** | Upload is cancelled on `dispose()`. `clear_media_sharing` RPC is called. R2 deletion queued. Members see "The host stopped sharing." |
| **Host's network drops mid-upload** | Retry current chunk 3× with exponential backoff. On reconnect (Supabase Realtime `connected` event), resume from last successful chunk. After 3 consecutive chunk failures, mark as `failed` and show retry button. |
| **Member's network drops mid-download** | On reconnect, resume via HTTP `Range` header from last written byte. Partial file is persisted to disk. Up to 5 reconnect retries. |
| **Member doesn't have enough disk space** | Pre-upload disk space check + opt-in dialog. If space runs out mid-download, catch the `FileSystemException`, show "Ran out of disk space" error, delete partial file, update readiness to `none`. |
| **Host's app is killed mid-upload** | On next app launch, if `media_upload_state == 'uploading'` for a room the user hosts, show a recovery dialog: "An upload was interrupted. Resume or cancel?" Resume re-requests a presigned URL (the old one may have expired) and uses multipart resume if possible. |
| **Room expires/ends during upload** | The `sweep_rooms` cron fires `retire_room`, which inserts into `pending_r2_deletions`. The Edge Function cleanup sweeps the R2 object. Client receives `room_ended` broadcast and cancels upload/download. |
| **R2 presigned URL expires before upload completes** | Presigned PUT URLs have a 1-hour expiry. For files > ~3 GB on slow connections, this could be insufficient. The client checks remaining time before each chunk; if < 5 minutes remain, it requests a fresh presigned URL from the Edge Function (for the same R2 key) before continuing. |
| **Multiple rooms sharing simultaneously** | Each room gets its own R2 key under `rooms/{room_id}/`. `MediaSharingService` is per-room (created in `RoomScreen` state, like `SyncService`). No global state conflicts. |
| **Free-tier quota race** | `record_upload_bytes` uses `FOR UPDATE` row-level lock on the profile to prevent two simultaneous uploads from double-spending the quota. |
| **Host toggles off, member is mid-download** | `sharing_toggled { enabled: false }` broadcast → member's download is cancelled → partial file deleted → snack "The host stopped sharing this file." |
| **Host switches to YouTube mode while upload is running** | Upload continues in background (unaffected by mode switch). A small indicator stays in the topbar showing upload progress even in YouTube mode. Host sees an option to "Cancel upload" or let it finish. |
| **Member leaves and rejoins** | On leave: download is cancelled, partial file deleted. On rejoin: if `media_upload_state == 'ready'`, show opt-in dialog again, start fresh download. |
| **Cloudflare R2 is unreachable** | Edge Function returns an error. Client shows "Cloud storage is temporarily unavailable — try again in a few minutes." `reportNonFatal` logs it. No crash. |
| **File > 5 GB (R2 single-PUT limit)** | Use S3 multipart upload. The Edge Function initiates the multipart upload and returns per-part presigned URLs. The client uploads parts in parallel (up to 3 concurrent). On completion, the Edge Function completes the multipart upload. |
| **OS storage permission denied** | On platforms requiring storage permission (Android), if denied, show a dialog explaining why it's needed with an "Open Settings" CTA. Re-check on app resume (`WidgetsBindingObserver.didChangeAppLifecycleState`). |

---

### 13. Cleanup Sweep & Data Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                       R2 Object Lifecycle                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Created:   When host gets presigned URL from Edge Function     │
│  Lives:     As long as the room is live AND sharing is toggled  │
│  Deleted:   ANY of:                                             │
│             • Host toggles sharing off                          │
│             • Room is retired (sweep_rooms / end_room)          │
│             • Cleanup cron finds orphaned uploads (>2h stale)   │
│             • R2 bucket lifecycle rule (safety net, 48h TTL)    │
│                                                                 │
│  Client cache (pt_downloads/) deleted:                          │
│             • Room no longer in list_my_rooms()                 │
│             • File older than 7 days                            │
│             • Host broadcasts sharing_toggled { enabled: false }│
│             • App uninstall (OS handles this)                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The R2 bucket should also have a **lifecycle rule** set via the Cloudflare dashboard as a safety net: auto-delete objects older than 48 hours. This catches anything the database-driven cleanup misses (e.g., if the cleanup Edge Function itself fails).

---

### 14. File Structure Summary

```
[NEW]  supabase/migrations/YYYYMMDDHHMMSS_media_sharing.sql
[NEW]  supabase/functions/media-upload-url/index.ts
[NEW]  supabase/functions/cleanup-r2/index.ts
[NEW]  lib/rooms/media_sharing_service.dart
[NEW]  lib/rooms/media_sharing_cache.dart
[NEW]  lib/rooms/widgets/media_sharing_toggle.dart
[NEW]  lib/rooms/widgets/download_opt_in_dialog.dart
[NEW]  lib/rooms/widgets/sharing_progress_indicator.dart
[MOD]  lib/sync/sync_events.dart                    — new event types
[MOD]  lib/sync/sync_service.dart                   — new broadcast/handler methods
[MOD]  lib/profile/entitlement_service.dart          — media sharing fields
[MOD]  lib/rooms/room_models.dart                    — R2/sharing fields on Room
[MOD]  lib/rooms/room_screen.dart                    — toggle UI, flows, gating
[MOD]  lib/rooms/room_service.dart                   — new RPC wrappers
[MOD]  lib/rooms/widgets/extend_room_dialog.dart     — premium perk list
[MOD]  lib/rooms/local_media_store.dart              — integration with cache cleanup
[MOD]  supabase/functions/.env.example               — R2 credentials
[MOD]  .env.example                                  — (no client changes needed)
```

---

### 15. Dependencies

**New Dart dependencies** (exact pins per convention):
- `path_provider` — for `getApplicationSupportDirectory()` (may already be transitive via other Flutter packages, needs verification).
- `minio` — S3-compatible Dart SDK. Handles multipart upload/download natively, including presigned URL consumption, chunked streaming, and resume. This is the chosen approach per the decision to prefer simpler repository code over zero new deps.

> [!NOTE]
> `dio` is **not** needed. `minio` handles the upload side, and `dart:io`'s `HttpClient` with `Range` headers is sufficient for download resume (downloads are simple GET requests against a presigned URL). This keeps the new dependency footprint to one package.

**New Edge Function dependencies:**
- `@aws-sdk/client-s3` — S3-compatible API for R2 (presigned URLs, multipart initiation/completion, delete).
- `@aws-sdk/s3-request-presigner` — presigned URL generation for both PUT (upload) and GET (download).

---

## Verification Plan

### Automated Tests

**Dart unit tests** (`fvm flutter test`):
- `test/media_sharing_service_test.dart` — upload/download state machine, retry logic, progress throttling, quota enforcement (using `SyncBackend` seam).
- `test/media_sharing_cache_test.dart` — file registration, cleanup rules, prune integration.
- `test/sync_logic_test.dart` — extend existing tests with media sharing gate interactions.

**pgTAP tests** (`supabase start && supabase test db`):
- `supabase/tests/media_sharing_test.sql` — `set_media_upload_state` host-only enforcement, `clear_media_sharing`, `record_upload_bytes` rolling window reset, `retire_room` R2 cleanup queueing, tier denormalization in `create_room`.

### Manual Verification

- **Happy path**: Host picks file → toggles sharing → members opt in → upload completes → members auto-download → gate opens → synced playback with the shared file.
- **Network interruption**: Kill network mid-upload, verify retry and resume. Kill network mid-download, verify Range-based resume.
- **Disk space**: Fill a test device's disk, verify the opt-in dialog shows "not enough space" and the host sees the member as not ready.
- **Tier gating**: Test as guest (no toggle visible), free (toggle visible, quota enforced), premium (unlimited).
- **Cleanup**: End a room, verify R2 object is deleted within 5 minutes. Toggle sharing off, verify immediate deletion.
- **Late joiner**: Join a room after upload completed, verify opt-in dialog and download work.
- **File switch lock**: With sharing on, try to pick a new file — verify it's blocked with explanation.
