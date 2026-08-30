# Media Sharing via Cloudflare R2

Host-initiated, per-room file sharing that lets a premium or quota-eligible host upload their local media file to Cloudflare R2, making it streamable and downloadable by every member in the room. The file is stored temporarily, deleted on room retirement or when the host toggles sharing off, and the entire lifecycle integrates seamlessly with the existing gate, presence, tier, sync, and security systems.

## User Review Required

> [!IMPORTANT]
> **Zero Member Wait Time via Direct `media_kit` Streaming.** Once the host finishes uploading to R2, room members do **not** need to wait for a multi-gigabyte file to download to disk before the watch party can start. `media_kit` (backed by `mpv`) natively streams directly from Cloudflare R2 presigned HTTPS URLs with HTTP Range-request support (`206 Partial Content`). Members can start watching immediately with 0 GB local disk usage, with an optional background download for offline caching.

> [!IMPORTANT]
> **Resumable S3 Multipart Upload Architecture (Zero Client SDK Bloat & Crash-Resistant).**
> - Standard single S3 `PutObject` requests have a **5 GB hard limit** and **cannot resume** interrupted streams.
> - To support up to **10 GB files** (Premium tier) and survive flaky mobile/Wi-Fi connections without restarting from 0%, uploads use **S3 Presigned Multipart Uploads** (10 MB chunks).
> - The Flutter client requires **zero AWS/S3 SDK dependencies**: Edge Functions mint batches of presigned part URLs, and the Dart client streams binary slices via `dart:io` `HttpClient` PUT requests while collecting the returned `ETag` headers.
> - **Memory & Boundary Correctness:** Slices are streamed directly from `File.openRead(start, end)` using Dart's **exclusive** `end` boundary (`file.openRead(startOffset, min(startOffset + partSizeBytes, totalFileSize))`) into the HTTP request body stream.
> - **Single-Subscription Stream Freshness on Retry:** Because `Stream<List<int>>` from `File.openRead` is a single-subscription stream, retrying a failed part must re-invoke `file.openRead(startOffset, endOffset)` freshly on each attempt rather than reusing an exhausted stream.
> - **Explicit `Content-Length` & SigV4 Header Alignment (Prevent 411 & Signature Mismatches):** Dart's `HttpClientRequest.addStream` defaults to `Transfer-Encoding: chunked` if length is omitted. S3/R2 endpoints reject chunked multipart part PUTs; `request.contentLength = chunkSizeBytes` is explicitly assigned before streaming. To prevent AWS SigV4 `SignatureDoesNotMatch` errors on presigned PUTs, the Dart client does not add ad-hoc `Content-Type` headers that were not included in the Edge Function's signed headers.
> - **Chunk Socket Timeouts:** Each chunk upload operation is wrapped in an explicit 60-second timeout (`uploadPartFuture.timeout(const Duration(seconds: 60))`) to protect against both frozen `request.addStream` buffers and unacknowledged TCP FIN drops on flaky mobile connections.
> - **S3 Minimum Part Size Boundary:** S3 requires all parts except the last to be $\ge 5\text{ MB}$. Files $\le 10\text{ MB}$ are uploaded as a single part (Part 1).
> - **Sliding-Window JIT Part URLs:** Part URLs are fetched just-in-time in sliding batches of **5–10 parts** (with 2–3 concurrent upload workers) to prevent 30-minute part URL expiration on slow mobile connections.
> - **Part Ordering, Case-Insensitive Headers & ETag Sanitization:** Part ETags returned by Cloudflare R2 are extracted via `response.headers.value(HttpHeaders.etagHeader)` (case-insensitive in `dart:io`), stripped of wrapping quotes (`.replaceAll('"', '').trim()`), and the parts array is strictly sorted in ascending order of `PartNumber` before completing the upload.
> - **Persistent Upload State, File Fingerprinting & Server-Side Part Discovery (`media-share/list-parts`):** Active upload session metadata (`uploadId`, `r2Key`, `fileSizeBytes`, `fileLastModified`, `completedParts`) is written locally to `LocalMediaStore` on every part completion. If the app is killed by the OS or restarts, the client verifies local file integrity (aborting if size/mtime changed) and discovers already uploaded parts via the `media-share/list-parts` Edge Function endpoint without re-uploading from 0%.

> [!IMPORTANT]
> **Consolidated Edge Function Architecture & Immediate Session Persistence.**
> - The 6 client-facing operations (`initiate`, `part-urls`, `list-parts`, `complete`, `abort`, `download-url`) are consolidated into a single Edge Function `supabase/functions/media-share/index.ts` with sub-actions.
> - **Immediate Multipart Key & Upload ID Persistence:** During `initiate`, the Edge Function creates the multipart upload on R2 and immediately records `media_r2_key`, `media_upload_id`, and `media_file_size` in `rooms` via `request_upload_slot(p_room_id, p_user_id, p_file_size, p_r2_key, p_upload_id)`. Passing `p_user_id` explicitly (extracted from the caller's verified JWT `user.id`) guarantees correct execution under the `service_role` client.
> - **Orphaned Multipart Session Purge on Re-Upload:** If a host initiates a new upload in a room that already had an incomplete upload, `request_upload_slot` automatically enqueues the old `(media_r2_key, media_upload_id)` into `pending_r2_deletions` before writing the new session.
> - **Strict Security Boundary:** All privileged state mutations and lock acquisitions (`request_upload_slot`, `set_media_upload_state`, `record_upload_bytes`) are granted strictly to `service_role` (`revoke execute ... from public, anon, authenticated; grant execute ... to service_role;`). The Edge Function validates caller JWT authenticity, room membership, and S3 multipart completion before executing state transitions, completely eliminating client RPC spoofing vectors.
> - Background garbage collection remains an independent scheduled worker (`supabase/functions/cleanup-r2/index.ts`).

> [!IMPORTANT]
> **Dynamic Session-Length Presigned Download URLs, Native `Media(start:)` & Mid-Playback 403 Recovery.**
> - Presigned GET URLs are **never stored in the database**. Authenticated room members fetch fresh presigned GET URLs minted on-demand via the `media-share/download-url` Edge Function endpoint.
> - **Session-Length Expiry:** Download URLs are minted with a TTL matching `min(remaining_room_session_seconds + 7200, 86400)` (up to 24 hours, matching Premium 24h room sessions), preventing mid-stream token expiration during watch marathons.
> - **RFC 5987 Unicode Header Formatting:** Filenames with non-ASCII or special characters are safely encoded using RFC 5987 / RFC 6266 (`filename*=UTF-8''...`), preventing S3 signature mismatches (`SignatureDoesNotMatch`).
> - **Native `Media(start:)` Demuxing:** Opening streams or resuming playback uses `Media(streamUrl, start: heldPosition)`, ensuring `mpv` demuxes directly at the target timestamp without a 0-second seek flash or transient `position = 0` broadcasts.
> - **Broadcast-Suppressed 403 Recovery & Track Preservation:** If a token drops or a network blip causes a 403 error during seek, the client transparently requests a fresh presigned URL and reopens the player at the held position with a broadcast suppression latch (`_isRecovering403 = true`). Active user-selected subtitle and audio tracks (`player.state.track.subtitle`, `player.state.track.audio`) are captured before reload and restored once demuxing completes.

> [!IMPORTANT]
> **Readiness Gate & Lockstep Sync Integration During Upload & Late Joining.**
> - When a host selects a local file and begins uploading, `rooms.media_upload_state` is set to `'uploading'`.
> - **Room-Level Gate Closure:** `evaluateGateState` evaluates to `.closed` while `media_upload_state == 'uploading'`, locking transport controls (play/pause/seek) room-wide until `media_upload_state == 'ready'`.
> - **Pure Member Readiness:** `memberSatisfiesGate` remains member-focused; members are not marked as individual gate blockers during upload. The `ReadinessOverlay` displays a room-wide upload progress banner (*"{hostName} is sharing {media_name}... ({percent}%, ~{eta} left)"*) while suppressing the "Locate your copy" button.
> - **Late Joiner Non-Blocking Fast-Path (No Room Pauses):** When a late joiner connects to a live room where shared media is already `ready` and playing, they auto-stream immediately and adopt the room position. The authority client automatically marks the late joiner as `waived` until their player reaches `ReadyStatus.ready`, preventing `evaluateGateState` from dropping to `.closed` and preventing unwanted room-wide pauses.
> - **Network Stream Watchdog:** The local load watchdog timeout is configured to 45 seconds for remote streams (vs 15s for local disk files) to allow `mpv`/`libavformat` to fetch `moov` atom headers over high-latency connections without triggering false "stalled" alerts.

> [!IMPORTANT]
> **Refined Anti-Abuse, Concurrency & Multi-Factor Auto-Healing Host Locks.**
> - **Global Concurrency Cap with Multi-Factor Auto-Healing:** Max **1 active upload per host globally**. `request_upload_slot` auto-clears the stale `active_upload_room_id` lock if:
>   1. The previous room is no longer live (`not is_room_live(...)`), OR
>   2. The previous room's upload state is no longer `'uploading'` (`media_upload_state in ('ready', 'failed', 'none')`), OR
>   3. The caller is no longer present or host in the previous room, OR
>   4. The previous upload lock is older than 30 minutes.
> - **Grace Window for Cancellations:** Quick cancellations ($< 50\text{ MB}$ uploaded or cancelled within 30 seconds) do **not** penalize the user.
> - **Exponential Cooldown on Consecutive Heavy Aborts:** Free-tier users who repeatedly abort heavy transfers (>50 MB) encounter exponential backoff cooldowns (1m $\rightarrow$ 5m $\rightarrow$ 15m) and a 10-session daily budget, preventing abuse without penalizing users with spotty internet.
> - **Emergency Kill-Switch:** Database-level configuration flag (`app_settings.media_sharing.enabled`) to instantly disable media sharing platform-wide if an anomaly is detected.

> [!IMPORTANT]
> **Quota Committed on Upload Completion, Not Initiation.** The free-tier weekly bandwidth limit (2.5 GB / 7 days) is tracked server-side in `profiles.r2_upload_bytes_7d`. Quota is only debited when an upload completes successfully (`media_upload_state == 'ready'`). If an upload fails, cancels, or is interrupted mid-stream, the user's weekly quota is preserved. Row-level `FOR UPDATE` locks prevent double-spending races.

> [!WARNING]
> **Storage, Mobile Backup Hygiene & Non-Disruptive Caching.**
> - On iOS/macOS, downloaded cache files must not balloon iCloud backups. Media cache files are stored in the platform cache/temporary directory (`getTemporaryDirectory()` / `pt_downloads/`) or explicitly marked with `NSURLIsExcludedFromBackupKey`.
> - If a member selects "Download to Device" while actively streaming, the background download finishes seamlessly without hot-swapping or re-opening the player mid-playback (preventing audio/video hitches). The cached file is registered in `LocalMediaStore` for instant local playback on subsequent seeks, replays, or room rejoins.

> [!WARNING]
> **Mobile Backgrounding & Foreground Auto-Resume.** On iOS/Android, background network sockets are aggressively throttled or suspended after 30 seconds. The app acquires `WakelockPlus` during uploads and displays an in-app banner warning hosts to keep PlayTogether in the foreground. If the host backgrounds the app, `MediaSharingService` automatically resumes from the last completed part chunk when the app returns to the foreground (`AppLifecycleState.resumed`).

> [!WARNING]
> **The Media-Switch Lock, Dormant Room Hygiene, Subtitle Tracks, and Host Succession.**
> - Embedded subtitle and audio tracks in `.mkv` / `.mp4` containers stream natively. External sidecar `.srt` files outside the video container are not uploaded to R2; host upload confirmation includes a helper note: *"Embedded subtitle tracks in MKV/MP4 stream automatically. External .srt files are not uploaded."*
> - While file sharing is active, switching media in the UI requires confirmation. If the host switches to YouTube or picks a new local file, the `set_room_media` RPC automatically queues `(media_r2_key, media_upload_id)` into `pending_r2_deletions` and resets upload state.
> - On room retirement (`retire_room`), if a room is kept dormant or persistent, any active R2 object or incomplete multipart upload is queued for deletion/abort and `rooms.media_r2_key`, `rooms.media_upload_id`, `rooms.media_file_size`, and `rooms.media_upload_state` are explicitly reset to `null` / `'none'` to prevent stale references upon room resumption.
> - If host succession occurs mid-stream, the incoming host inherits full authority to toggle off or clear the shared media.

---

## Resolved Decisions

| Decision | Resolution |
|---|---|
| **R2 bucket provisioning** | Manual one-time creation via Cloudflare dashboard ($0.00 egress, 10 GB free storage). Setup guide below. |
| **Upload architecture** | **S3 Presigned Multipart Uploads** (10 MB chunks). Enables $>5\text{ GB}$ files, streaming direct from disk without RAM bloat, fresh per-attempt stream slicing, 60s chunk timeouts, and chunk-level resume with zero S3 SDK dependencies on Flutter client. |
| **Dart slicing & SigV4 header alignment** | **Exclusive end boundary:** `file.openRead(startOffset, min(startOffset + partSizeBytes, totalFileSize))` with explicit `request.contentLength` to prevent 411 chunked rejection. Avoids un-signed custom `Content-Type` headers in client PUTs to prevent SigV4 mismatches. |
| **Resume & Crash Persistence** | Local cache in `LocalMediaStore` / `shared_preferences` tracking `completedParts`, `fileSizeBytes`, `fileLastModified` + file modification validation + Edge Function `media-share/list-parts` fallback (safely handling empty `response.Parts ?? []`). |
| **Edge Function topology** | Consolidated router (`supabase/functions/media-share`) for all 6 client operations to reduce cold starts and share warm S3 client isolates + standalone `cleanup-r2` worker. |
| **Database security boundary** | `request_upload_slot`, `set_media_upload_state`, and `record_upload_bytes` granted strictly to `service_role`; Edge Function validates caller JWT authenticity, host role, and S3 upload completion before committing DB state. |
| **Playback architecture** | **Direct streaming via `media_kit(Media(presignedGetUrl))`** for instant start upon upload completion. Embedded subtitle tracks (.mkv/.mp4) stream natively. Optional background Range-based download to local cache with non-disruptive completion. |
| **High-Bitrate Guidance** | Member prompt calculates estimated stream bitrate only when probed duration is available (`media_duration_ms > 0`), displaying "Download to Device (Recommended)" when stream bitrate exceeds $15\text{ Mbps}$, falling back cleanly to file size if unprobed. |
| **Download URL delivery** | Ephemeral presigned GET URLs minted on-demand via `media-share/download-url` with TTL matching room session duration (up to 24h), RFC 5987 Unicode filename encoding, native `Media(start: heldPosition)` demuxing, and broadcast-suppressed 403 recovery with subtitle/audio track preservation. |
| **Late joiner experience** | Auto-streams directly upon joining an active session with automatic temporary gate waiver until ready, eliminating blocking dialogs and preventing room-wide pause glitches. |
| **Canonical media reuse** | Reuses existing `rooms.media_name` column — eliminates duplicate `media_file_name` column to prevent desynchronization bugs. |
| **Free-tier bandwidth tracking** | Server-side in database with weekly tumbling window (2.5 GB / 7 days), committed strictly on upload completion with `FOR UPDATE` row lock. |
| **Anti-Abuse & Concurrency** | 1 global active upload cap with multi-factor stale-lock auto-clearing, same-room re-upload orphan cleanup, grace window for quick cancels, exponential backoff on heavy aborts, Edge Function rate limiting. |
| **Readiness gate integration** | Room-level gate closure in `evaluateGateState` while uploading; members remain non-blocking until media is ready; watchdog extended to 45s for network streams. |
| **Postgres Constraints & Listings** | Recreates `list_my_rooms()` with new columns + re-grants to `authenticated`; updates `rooms_media_shape_chk` constraint with strict local state checks (`media_upload_id is null` on `ready`). |
| **Dormant room hygiene** | `retire_room` purges R2 objects/multipart sessions and resets `media_r2_key`, `media_upload_id`, `media_upload_state = 'none'` even for persistent/dormant rooms. |
| **Disk space checking** | Optional check using `storage_space` plugin only if member chooses offline download. Streaming requires 0 GB disk. |
| **R2 cleanup failsafe** | 4-layer cleanup: Immediate DB RPC on cancel/switch/retire/re-upload + scheduled `cleanup-r2` Edge Function + 24-hour Cloudflare R2 bucket lifecycle rule + 12-hour incomplete multipart abort rule. |

---

## Prerequisite: Cloudflare R2 Setup Guide

Cloudflare R2 is a **separate service** from Supabase Storage. Supabase's free-tier storage (1 GB storage, 2 GB bandwidth/month) is insufficient for video files. R2's free tier provides **10 GB storage** and **$0.00 egress** (unlimited download/streaming bandwidth), making it ideal for video sharing.

### One-time setup steps:

1. **Create a Cloudflare account** at [dash.cloudflare.com](https://dash.cloudflare.com).

2. **Enable R2** in the Cloudflare dashboard:
   - Navigate to **R2 Object Storage** in the left sidebar.
   - Accept the R2 terms (free tier includes 10 GB storage + 10M Class B requests/month with zero egress fees).

3. **Create the bucket**:
   - Click **Create bucket**.
   - Name: `playtogether-media` (or your preference).
   - Location hint: **Automatic** (Cloudflare routes to nearest region).
   - Default storage class: **Standard**.

4. **Set up lifecycle rules** (safety net for orphaned & incomplete files):
   - Go to the bucket → **Settings** → **Object lifecycle rules**.
   - Add rule 1: **Delete uploaded objects** older than **24 hours**.
   - Add rule 2: **Abort incomplete multipart uploads** older than **12 hours**.
   - This serves as a hard secondary failsafe behind the database-driven cleanup.

5. **Configure CORS on R2 bucket**:
   - In bucket settings → **CORS Policy**, add:
     ```json
     [
       {
         "AllowedOrigins": ["*"],
         "AllowedMethods": ["GET", "PUT", "HEAD"],
         "AllowedHeaders": ["*", "Range"],
         "ExposeHeaders": ["ETag", "Content-Range", "Accept-Ranges", "Content-Length"],
         "MaxAgeSeconds": 3600
       }
     ]
     ```

6. **Set up Cloudflare Billing Alert**:
   - Go to **Manage Account** → **Billing** → **Preferences** / **Notifications**.
   - Set an alert threshold at **$1.00** and **$5.00** for early warning.

7. **Create an API token** for Edge Functions:
   - Go to **R2 Object Storage** → **Manage R2 API tokens** → **Create API token**.
   - Permissions: **Object Read & Write** on the `playtogether-media` bucket only.
   - Copy the **Access Key ID** and **Secret Access Key**.

8. **Note your Account ID**:
   - Visible in the Cloudflare dashboard URL: `dash.cloudflare.com/<account-id>/...`
   - Or: **Overview** page → right sidebar → **Account ID**.

9. **Add credentials to Edge Functions**:
   ```bash
   # In supabase/functions/.env, add:
   CF_R2_ACCOUNT_ID=<your-account-id>
   CF_R2_ACCESS_KEY_ID=<from-step-7>
   CF_R2_SECRET_ACCESS_KEY=<from-step-7>
   CF_R2_BUCKET_NAME=playtogether-media
   CF_R2_ENDPOINT=https://<your-account-id>.r2.cloudflarestorage.com
   ```

10. **Deploy the secrets**:
    ```bash
    supabase secrets set --env-file supabase/functions/.env
    ```

### R2 Free Tier Limits & Unit Costs:
| Resource | Free Allowance | Overage | Notes for Video Sharing |
|---|---|---|---|
| Storage | 10 GB / month | $0.015 / GB-month | Negligible (fractions of a cent) due to 24h auto-purge |
| Class A ops (PUT, Multipart, LIST) | 1,000,000 / month | $4.50 / million | ~100-500 ops per multipart upload (~$0.0018 per upload) |
| Class B ops (GET, HEAD) | 10,000,000 / month | $0.36 / million | Stream Range requests (~200-500 ops per 2h movie) |
| **Egress (downloads & streams)** | **Unlimited — $0.00 forever** | N/A | **Zero bandwidth charges** |

---

## Anti-Abuse, DDoS & Cost Protection Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       Multi-Layer Defense Matrix                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  [Layer 1: Edge Function Gateway (media-share)]                         │
│    • Rate Limit: Max 10 upload sessions / 24h per free user             │
│    • Auth & Room Presence Verification (Valid Supabase JWT)             │
│    • Global Kill-Switch Check (`app_settings.media_sharing.enabled`)    │
│    • File Size & Whitelist Verification (video/* only, <= 4GB / <= 10GB)│
│    • Immediate DB persistence of r2_key & upload_id on initiate         │
│    • Privileged DB calls via service_role client only                   │
│                                                                         │
│  [Layer 2: Database Concurrency & Multi-Factor Auto-Healing]             │
│    • Concurrency Lock: 1 active upload per host globally                │
│    • Multi-Factor Auto-Healing: Clears lock if room dead, state not     │
│      uploading, host absent, or lock > 30m old                          │
│    • Same-room re-upload orphan cleanup to pending_r2_deletions         │
│    • Grace Window: Quick cancels (<50MB / <30s) incur no penalty        │
│    • Exponential Backoff on consecutive heavy aborts (1m -> 5m -> 15m)  │
│    • Row Lock (`FOR UPDATE`) on profiles during quota checks            │
│                                                                         │
│  [Layer 3: S3 Multipart Cryptographic & Stream Constraints]             │
│    • S3 min part size: 10MB chunks (files <= 10MB uploaded as 1 part)   │
│    • Exclusive boundary handling in Dart (`openRead(s, min(s+sz, tot))`)│
│    • Explicit `Content-Length` assigned before `addStream`              │
│    • Sliding-window JIT batch part URL generation (5-10 parts, 30m TTL) │
│    • Sanitized ETags and strictly ordered PartNumber completion array   │
│    • Local state persistence + `media-share/list-parts` resume          │
│    • Fixed `Content-Type` matching declared video format                │
│                                                                         │
│  [Layer 4: 4-Tier Storage Cleanup & Budget Safeguards]                  │
│    • Immediate DB `pending_r2_deletions` queue on cancel, switch, retire│
│    • Scheduled `cleanup-r2` worker sweeping orphans every 5 minutes     │
│    • Cloudflare R2 bucket 24-hour auto-purge lifecycle rule             │
│    • Cloudflare R2 bucket 12-hour abort incomplete multipart rule       │
│    • Cloudflare $1.00 budget alerts + Supabase Spend Caps               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Abuse Vectors & Mitigations:

1. **Upload-Cancel Griefing (Repeatedly streaming 3.9 GB and cancelling):**
   - **Mitigation:**
     - **Grace Window vs Heavy Abort:** Cancellations with $< 50\text{ MB}$ uploaded do not trigger penalties. Cancellations of heavy uploads increment consecutive abort counters, triggering exponential cooldowns (1 min, 5 min, 15 min lockout).
     - **Concurrency Lock:** Max 1 active upload attempt globally per user.
     - **Instant Purge & S3 Abort:** Edge Function immediately aborts the multipart upload in R2 so partial data is discarded.

2. **File Size / Payload Spoofing (Declaring 10 MB but uploading 10 GB):**
   - **Mitigation:**
     - The S3 Multipart completion step verifies the sum of uploaded parts against declared limits.
     - Edge Function refuses to mint part URLs beyond the declared file size and user tier ceiling (2.0 GB for free, 10 GB for premium).

3. **Edge Function Compute Flooding:**
   - **Mitigation:**
     - Part URLs are minted in sliding batches of 5–10 parts just-in-time, reducing invocation volume while preventing token expiry on slow uplinks.
     - In-memory / DB rate limiting: Max 10 upload sessions per day for free tier.
     - Mandatory authenticated JWT; unauthenticated or guest callers rejected with 401.

4. **Malware / Non-Video Hosting Abuse & DMCA Safe Harbor:**
   - **Mitigation:**
     - Presigned URLs are constrained to MIME types matching `video/*` (`video/mp4`, `video/x-matroska`, `video/webm`, `video/quicktime`, `video/x-msvideo`).
     - Downloads are gated behind room presence checks; URLs are not public.
     - Namespaced R2 key pattern: `rooms/${roomId}/${crypto.randomUUID()}-${sanitizedFileName}`.
     - Terms of Service explicitly state ephemeral hosting terms with DMCA takedown adherence.
     - Database kill-switch allows immediate shutdown of the feature if needed.

---

## Proposed Changes

### 1. Database Schema — New Migration

#### [NEW] `supabase/migrations/YYYYMMDDHHMMSS_media_sharing.sql`

Adds the columns, tables, constraints, and RPCs needed for media sharing state, bandwidth tracking, concurrency locks, and deletion queueing.

**Global Platform Settings (Emergency Kill-Switch):**
```sql
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

-- Seed media sharing master switch (enabled by default)
insert into public.app_settings (key, value)
values ('media_sharing', '{"enabled": true, "free_tier_max_file_bytes": 2147483648, "premium_max_file_bytes": 10737418240}'::jsonb)
on conflict (key) do nothing;
```

**Schema changes on `rooms` (Reusing `media_name` as canonical name):**
```sql
alter table public.rooms
  add column media_file_size bigint
    check (media_file_size > 0),
  add column media_r2_key text
    check (char_length(media_r2_key) between 1 and 512),
  add column media_upload_id text
    check (char_length(media_upload_id) between 1 and 512),
  add column media_upload_state text not null default 'none'
    check (media_upload_state in ('none', 'uploading', 'ready', 'failed')),
  add column media_sharing_level text not null default 'none'
    check (media_sharing_level in ('none', 'limited', 'full'));

-- Update shape constraint to ensure R2 columns are strictly consistent
alter table public.rooms
  drop constraint if exists rooms_media_shape_chk;

alter table public.rooms
  add constraint rooms_media_shape_chk check (
    case media_kind
      when 'none' then
        media_name is null and media_duration_ms is null and media_url is null
        and media_r2_key is null and media_file_size is null and media_upload_id is null
        and media_upload_state = 'none'
      when 'local' then
        media_name is not null and media_url is null
        and (
          (media_upload_state = 'none' and media_r2_key is null and media_file_size is null and media_upload_id is null)
          or (media_upload_state in ('uploading', 'failed'))
          or (media_upload_state = 'ready' and media_r2_key is not null and media_file_size is not null and media_upload_id is null)
        )
      when 'youtube' then
        media_url is not null and media_r2_key is null and media_file_size is null
        and media_upload_id is null and media_upload_state = 'none'
      else false
    end
  );
```

**Schema changes on `profiles` (Quota & Abuse Controls):**
```sql
alter table public.profiles
  add column r2_upload_bytes_7d bigint not null default 0,
  add column r2_upload_window_start timestamptz not null default now(),
  add column r2_consecutive_aborts int not null default 0,
  add column r2_cooldown_until timestamptz,
  add column active_upload_room_id uuid references public.rooms(id) on delete set null,
  add column active_upload_started_at timestamptz;
```

**Schema changes on `tier_limits`:**
```sql
alter table public.tier_limits
  add column media_sharing text not null default 'none'
    check (media_sharing in ('none', 'limited', 'full')),
  add column media_sharing_weekly_bytes bigint not null default 0;

update public.tier_limits set media_sharing = 'none', media_sharing_weekly_bytes = 0 where tier = 'guest';
update public.tier_limits set media_sharing = 'limited', media_sharing_weekly_bytes = 2684354560 where tier = 'free';
update public.tier_limits set media_sharing = 'full', media_sharing_weekly_bytes = 0 where tier = 'premium';
```

**Pending R2 Deletions Queue:**
```sql
create table public.pending_r2_deletions (
  id bigint generated always as identity primary key,
  r2_key text not null,
  upload_id text, -- Non-null if an incomplete multipart upload needs aborting
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

-- RLS: Service role only
alter table public.pending_r2_deletions enable row level security;
```

**Update `list_my_rooms()` RPC (Drop, Recreate & Re-grant):**
```sql
drop function if exists public.list_my_rooms();

create function public.list_my_rooms()
returns table (
  id uuid,
  code text,
  name text,
  created_by uuid,
  created_at timestamptz,
  duration_minutes int,
  expires_at timestamptz,
  ended_at timestamptz,
  resumable_until timestamptz,
  persistent boolean,
  dormant_hours int,
  av_level text,
  max_members int,
  transport_lock boolean,
  media_kind text,
  media_name text,
  media_duration_ms bigint,
  media_url text,
  media_updated_at timestamptz,
  media_position_ms bigint,
  media_position_at timestamptz,
  media_file_size bigint,
  media_r2_key text,
  media_upload_state text,
  media_sharing_level text,
  state text,
  role text,
  member_count int,
  is_owner boolean,
  is_member boolean
)
language sql stable security definer set search_path = ''
as $$
  select
    r.id, r.code, r.name, r.created_by, r.created_at, r.duration_minutes,
    r.expires_at, r.ended_at, r.resumable_until, r.persistent, r.dormant_hours,
    r.av_level, r.max_members, r.transport_lock,
    r.media_kind, r.media_name, r.media_duration_ms, r.media_url, r.media_updated_at,
    r.media_position_ms, r.media_position_at,
    r.media_file_size, r.media_r2_key, r.media_upload_state, r.media_sharing_level,
    public.room_state(r),
    m.role,
    (select count(*)::int from public.room_members x where x.room_id = r.id),
    r.created_by = (select auth.uid()),
    m.user_id is not null
  from public.rooms r
  left join public.room_members m
    on m.room_id = r.id and m.user_id = (select auth.uid())
  where (select auth.uid()) is not null
    and (m.user_id is not null or r.created_by = (select auth.uid()))
    and public.room_state(r) in ('live', 'dormant')
  order by (public.room_state(r) = 'live') desc, r.created_at desc;
$$;

revoke execute on function public.list_my_rooms() from public, anon;
grant execute on function public.list_my_rooms() to authenticated;
```

**New & Modified RPCs:**

1. **Update `create_room(p_name text, p_duration_minutes int)`:**
   - In `create_room`, assign `media_sharing_level = v_limits.media_sharing` when inserting the new `rooms` row:
     ```sql
     insert into public.rooms (
       code, name, created_by, duration_minutes, expires_at,
       persistent, dormant_hours, av_level, max_members, media_sharing_level)
     values (
       v_code, coalesce(nullif(left(trim(p_name), 60), ''), 'Watch party'),
       v_uid, p_duration_minutes, now() + make_interval(mins => p_duration_minutes),
       v_limits.persistent_room_cap > 0, v_limits.dormant_hours,
       v_limits.av_level, v_limits.max_members, v_limits.media_sharing)
     ```

2. **Update `set_room_media(...)` to clean up R2 objects on media switch:**
   - If `v_room.media_r2_key` is present (or `v_room.media_upload_id` is present) AND (`v_kind != 'local'` OR `v_name != v_room.media_name`):
     ```sql
     insert into public.pending_r2_deletions (r2_key, upload_id)
     values (v_room.media_r2_key, v_room.media_upload_id);

     update public.rooms set
       media_r2_key = null,
       media_upload_id = null,
       media_file_size = null,
       media_upload_state = 'none'
     where id = p_room_id;
     ```

3. `request_upload_slot(p_room_id uuid, p_user_id uuid, p_file_size bigint, p_r2_key text, p_upload_id text)`:
   - `security definer`. **Restricted to `service_role` only** (`revoke execute on function public.request_upload_slot(uuid, uuid, bigint, text, text) from public, anon, authenticated; grant execute on function public.request_upload_slot(uuid, uuid, bigint, text, text) to service_role;`).
   - Invoked exclusively by the `media-share/initiate` Edge Function with the verified caller's `user.id`.
   - Validates that `p_user_id` is the host of `p_room_id` and room is live.
   - **Precondition Check:** Validates that `rooms.media_kind = 'local'` and `rooms.media_name is not null` (ensuring consistency with `rooms_media_shape_chk`).
   - Checks global kill-switch (`app_settings -> media_sharing -> enabled`).
   - Locks profile row: `select * from public.profiles where id = p_user_id for update`.
   - Checks caller cooldown (`r2_cooldown_until is null or r2_cooldown_until <= now()`).
   - **Multi-Factor Stale Lock Auto-Clearing:**
     ```sql
     if v_profile.active_upload_room_id is not null and v_profile.active_upload_room_id != p_room_id then
       declare
         v_prev_live boolean := public.is_room_live(v_profile.active_upload_room_id);
         v_prev_state text;
         v_prev_host boolean;
       begin
         select media_upload_state into v_prev_state from public.rooms where id = v_profile.active_upload_room_id;
         select exists(select 1 from public.room_members where room_id = v_profile.active_upload_room_id and user_id = p_user_id and role = 'host') into v_prev_host;

         if (not v_prev_live)
            or (v_prev_state is distinct from 'uploading')
            or (not v_prev_host)
            or (v_profile.active_upload_started_at < now() - interval '30 minutes') then
           update public.profiles set active_upload_room_id = null, active_upload_started_at = null where id = p_user_id;
         else
           raise exception 'active_upload_in_progress';
         end if;
       end;
     end if;
     ```
   - **Orphaned Multipart Cleanup on Same-Room Re-upload:**
     ```sql
     if v_room.media_upload_id is not null and v_room.media_upload_id != p_upload_id then
       insert into public.pending_r2_deletions (r2_key, upload_id)
       values (v_room.media_r2_key, v_room.media_upload_id);
     end if;
     ```
   - Checks weekly quota if `media_sharing_level == 'limited'`:
     - Resets tumbling window if `r2_upload_window_start < now() - interval '7 days'`:
       `update public.profiles set r2_upload_window_start = now(), r2_upload_bytes_7d = 0 where id = p_user_id;`
     - Validates `r2_upload_bytes_7d + p_file_size <= weekly_limit`.
   - Sets `profiles.active_upload_room_id = p_room_id`, `profiles.active_upload_started_at = now()`, and writes session to `rooms`:
     ```sql
     update public.rooms set
       media_upload_state = 'uploading',
       media_file_size = p_file_size,
       media_r2_key = p_r2_key,
       media_upload_id = p_upload_id
     where id = p_room_id;
     ```

4. `set_media_upload_state(p_room_id uuid, p_user_id uuid, p_state text, p_file_size bigint default null, p_r2_key text default null, p_bytes_uploaded bigint default 0)`:
   - `security definer`. **Restricted to `service_role` only** (`revoke execute ... from public, anon, authenticated; grant execute ... to service_role;`).
   - Updates `media_upload_state`, `media_file_size`, and `media_r2_key`.
   - When transitioning to `'ready'`:
     - Clears `media_upload_id = null` on `rooms` (multipart upload is now completed).
     - Clears `profiles.active_upload_room_id = null`, `profiles.active_upload_started_at = null` for `p_user_id`.
     - Resets `profiles.r2_consecutive_aborts = 0`.
     - Debits weekly quota via `record_upload_bytes(p_user_id, p_file_size)` if room is `'limited'`.
   - When transitioning to `'failed'`:
     - Clears `profiles.active_upload_room_id = null`, `profiles.active_upload_started_at = null`.
     - If `p_bytes_uploaded > 52428800` (50 MB), increments `profiles.r2_consecutive_aborts` and applies backoff cooldown (1m $\rightarrow$ 5m $\rightarrow$ 15m).
     - Queues `(p_r2_key, media_upload_id)` into `pending_r2_deletions`.

5. `clear_media_sharing(p_room_id uuid, p_bytes_uploaded bigint default 0)`:
   - Host only (or acting host after succession).
   - If state was `'uploading'`:
     - Clears `active_upload_room_id` and `active_upload_started_at` on `profiles` where `active_upload_room_id = p_room_id` (guaranteeing lock cleanup even if host succession occurred).
     - If `p_bytes_uploaded > 52428800`, increments `r2_consecutive_aborts` and applies cooldown to the uploader.
   - If `media_r2_key` is present or `media_upload_id` is present, inserts into `pending_r2_deletions (r2_key, upload_id) values (v_room.media_r2_key, v_room.media_upload_id)`.
   - Nulls out `media_r2_key`, `media_upload_id`, `media_file_size` and sets `media_upload_state = 'none'`.

6. `record_upload_bytes(p_user_id uuid, p_bytes bigint)`:
   - `security definer`. **Restricted to `service_role` only**.
   - Row-locks profile (`select * from public.profiles where id = p_user_id for update`).
   - If `r2_upload_window_start < now() - interval '7 days'`, resets window timestamp to `now()` and initializes bytes to `p_bytes`.
   - Else increments `r2_upload_bytes_7d = r2_upload_bytes_7d + p_bytes`.

7. **Integration into `retire_room(p_room_id uuid)` (with Incomplete Multipart & Dormant Room Hygiene):**
   - Before deleting or archiving the room, if `media_r2_key` is not null or `media_upload_id` is not null:
     ```sql
     if v_room.media_r2_key is not null or v_room.media_upload_id is not null then
       insert into public.pending_r2_deletions (r2_key, upload_id)
       values (v_room.media_r2_key, v_room.media_upload_id);

       -- Clear R2 state on rooms so dormant/persistent rooms do not reference purged files
       update public.rooms set
         media_r2_key = null,
         media_upload_id = null,
         media_file_size = null,
         media_upload_state = 'none'
       where id = p_room_id;
     end if;
     ```
   - Clears `profiles.active_upload_room_id` and `active_upload_started_at` where `active_upload_room_id = p_room_id`.

---

### 2. Supabase Edge Functions

#### [NEW] `supabase/functions/media-share/index.ts`

Consolidated Edge Function router handling all client-facing media sharing actions. Uses a shared `S3Client` instance across warm Deno isolates to minimize cold-start latency. Uses the user's JWT to authenticate incoming requests, and the `service_role` client for privileged database mutations.

**Shared Setup:**
```ts
import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import {
  S3Client,
  CreateMultipartUploadCommand,
  UploadPartCommand,
  ListPartsCommand,
  CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand,
  GetObjectCommand,
} from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const s3 = new S3Client({
  region: "auto",
  endpoint: Deno.env.get("CF_R2_ENDPOINT")!,
  credentials: {
    accessKeyId: Deno.env.get("CF_R2_ACCESS_KEY_ID")!,
    secretAccessKey: Deno.env.get("CF_R2_SECRET_ACCESS_KEY")!,
  },
});
const bucketName = Deno.env.get("CF_R2_BUCKET_NAME")!;

// Service role client for privileged DB operations
const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
```

**Actions handled via URL path / request body:**

1. **`POST /media-share/initiate`**
   - **Guards:** Valid JWT, MIME type whitelist (`video/*`), host verification.
   - Generates namespaced R2 key: `rooms/${roomId}/${crypto.randomUUID()}-${sanitizedFileName}`.
   - S3 Part Sizing: $\le 10\text{ MB} \rightarrow 1\text{ part}$, else $\text{ceil}(\text{fileSize} / 10\text{MB})$.
   - Executes `CreateMultipartUploadCommand` on Cloudflare R2 with declared `ContentType`.
   - Calls `supabaseAdmin.rpc('request_upload_slot', { p_room_id: roomId, p_user_id: user.id, p_file_size: fileSize, p_r2_key: r2Key, p_upload_id: uploadId })`.
   - If slot acquisition fails (e.g. quota exceeded or cooldown active), immediately executes `AbortMultipartUploadCommand` on R2 and returns error.
   - Returns `{ uploadId, r2Key, partSizeBytes: 10485760, totalParts }`.

2. **`POST /media-share/part-urls`**
   - **Guards:** Host verification, active upload lock match.
   - Accepts `{ uploadId, r2Key, partNumbers: [1, 2, ..., 10] }`.
   - Generates presigned `UploadPartCommand` URLs (30-minute TTL) in sliding batches without restricting `ContentType` so client binary streams upload without SigV4 header mismatches.
   - Returns `{ parts: [{ partNumber: 1, url: "https://..." }, ...] }`.

3. **`POST /media-share/list-parts`**
   - **Guards:** Host verification.
   - Accepts `{ uploadId, r2Key }`.
   - Executes `ListPartsCommand` on Cloudflare R2.
   - Returns already uploaded parts: `{ parts: (response.Parts ?? []).map(p => ({ partNumber: p.PartNumber, etag: p.ETag, size: p.Size })) }` allowing client to resume without re-uploading from 0%.

4. **`POST /media-share/complete`**
   - **Guards:** Host verification.
   - Accepts `{ roomId, uploadId, r2Key, fileSize, parts: [{ partNumber, etag }] }`.
   - **ETag Sanitization & Part Ordering:** Strips quotes (`etag.replace(/^"|"$/g, '')`) and sorts parts strictly ascending by `partNumber`.
   - Executes `CompleteMultipartUploadCommand`.
   - Calls `supabaseAdmin.rpc('set_media_upload_state', { p_room_id: roomId, p_user_id: user.id, p_state: 'ready', p_file_size: fileSize, p_r2_key: r2Key })`.
   - Returns `{ success: true, state: "ready" }`.

5. **`POST /media-share/abort`**
   - Executes `AbortMultipartUploadCommand` on Cloudflare R2.
   - Calls `clear_media_sharing` RPC to reset state and clear upload lock.
   - Returns `{ success: true }`.

6. **`POST /media-share/download-url`**
   - **Guards:** Verified room membership, active room check, `media_upload_state == 'ready'`.
   - Session-Length TTL calculation: `min(remaining_session_seconds + 7200, 86400)`.
   - **RFC 5987 Unicode Filename Formatting:**
     ```ts
     const safeAscii = fileName.replace(/[^\x20-\x7E]/g, "_").replace(/"/g, '\\"');
     const encodedUtf8 = encodeURIComponent(fileName);
     const contentDisposition = `inline; filename="${safeAscii}"; filename*=UTF-8''${encodedUtf8}`;
     ```
   - Executes presigned `GetObjectCommand` with `ResponseContentDisposition: contentDisposition`.
   - Returns `{ streamUrl, fileName, fileSize, expiresIn: ttlSeconds }`.

---

#### [NEW] `supabase/functions/cleanup-r2/index.ts`

Scheduled worker (triggered via `pg_cron` + `pg_net` / Supabase Cron every 5 minutes):
- Reads up to 50 rows from `pending_r2_deletions`.
- If `upload_id` is present, executes `AbortMultipartUploadCommand`; otherwise executes `DeleteObjectCommand`.
- Deletes processed rows from `pending_r2_deletions`.
- Increments `attempts` on failure; drops rows exceeding 5 failed attempts.
- Sweeps rooms stuck in `'uploading'` state for $> 2\text{ hours}$ and aborts their uploads using the stored `media_upload_id` and `media_r2_key`.
- Sweeps unclaimed expired staged uploads (`staged_media_uploads`) and aborts/deletes their R2 objects.
- **Fail-Safe Deletion Triggers**: `BEFORE DELETE` triggers on `public.rooms` and `public.staged_media_uploads` guarantee that whenever a room or staged upload is deleted (manual, RPC, or cascading), any attached R2 keys/upload IDs are automatically pushed to `pending_r2_deletions`.

---

### 3. Client-Side Dart — Media Sharing & Playback Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Resumable Media Sharing Architecture                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  [Host]                                                                 │
│    │                                                                    │
│    ├─► 1. Initiate Upload ──► Edge Function (media-share/initiate)      │
│    │                          └─► R2 CreateMultipartUpload + DB Lock    │
│    │                          └─► Returns uploadId, totalParts          │
│    │                          └─► Saves upload session to LocalMediaStore│
│    │                                                                    │
│    ├─► 2. Get Part URLs ────► Edge Function (media-share/part-urls)     │
│    │                          └─► Sliding batches of 5-10 parts (JIT)   │
│    │                                                                    │
│    ├─► 3. Stream Chunks ────► Cloudflare R2 (2-3 Concurrent PUTs)       │
│    │                          └─► Exclusive boundary: openRead(s, end)  │
│    │                          └─► request.contentLength = chunkBytes    │
│    │                          └─► No un-signed custom Content-Type      │
│    │                          └─► Collects & sanitizes ETag headers     │
│    │                          └─► Persists completed parts locally      │
│    │                          └─► Auto-resumes on foreground / retry    │
│    │                                                                    │
│    ├─► 4. Progress Sync ────► Supabase Realtime (Throttled >= 3.0s)     │
│    │                          └─► Client dead-reckoning interpolation   │
│    │                                                                    │
│    └─► 5. Complete Upload ──► Edge Function (media-share/complete)      │
│                               └─► Sends sorted Parts list               │
│                               └─► Commits DB state 'ready' & quota      │
│                                                                         │
│  [Room Members]                                                         │
│    │                                                                    │
│    ├─► 1. Receive State 'ready' (via Realtime room update / broadcast)  │
│    ├─► 2. Fetch Presigned GET ─► Edge Function (media-share/download-url│
│    │                          └─► Session-Length Stream URL             │
│    │                                                                    │
│    ├───► [FAST PATH - Instant Stream (Default & Late Joiners)]          │
│    │       └─► Pass Stream URL directly to media_kit:                   │
│    │             _adoptRemoteStream(streamUrl, fileName)                │
│    │             player.open(Media(streamUrl, start: heldPosition))     │
│    │             ReadyStatus -> .ready (Instant! 0s wait, 0GB disk)     │
│    │             Suppressed 403 Refresher + track restoration fallback  │
│    │                                                                    │
│    └───► [OPTIONAL PATH - Offline Download / Cache]                     │
│            └─► Stream to cache dir via HTTP Range                       │
│                  Save to pt_downloads/{room_id}/                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### [NEW] `lib/rooms/media_sharing_service.dart`

Singleton service managing resumable multipart upload streaming, transparent download URL refreshes, and cache management.

**Key Implementation Standards:**
1. **Low-Memory Resumable Chunk Slicing & Single-Subscription Freshness (Exclusive End Boundary):**
   ```dart
   // Dart's File.openRead(start, end) has an EXCLUSIVE 'end' byte offset.
   // Note: File.openRead returns a single-subscription stream; retries MUST call openRead freshly.
   Stream<List<int>> createChunkStream(int partNumber) {
     final startOffset = (partNumber - 1) * partSizeBytes;
     final endOffset = math.min(startOffset + partSizeBytes, totalFileSize);
     return file.openRead(startOffset, endOffset);
   }
   ```

2. **Explicit `Content-Length`, Full-Operation Timeout & Case-Insensitive ETag Handling:**
   ```dart
   Future<String> uploadPartWithTimeout(int partNumber, String partUrl) async {
     return Future<String>(() async {
       final request = await _httpClient.putUrl(Uri.parse(partUrl));
       request.contentLength = endOffset - startOffset; // Prevents S3 411 Length Required chunked rejection
       // Note: Do not set ad-hoc custom Content-Type headers on presigned PUTs to prevent SigV4 SignatureDoesNotMatch mismatches
       await request.addStream(createChunkStream(partNumber));
       final response = await request.close();
       if (response.statusCode != HttpStatus.ok) {
         throw HttpException('Part $partNumber upload failed with status ${response.statusCode}');
       }
       final rawEtag = response.headers.value(HttpHeaders.etagHeader) ?? '';
       return rawEtag.replaceAll('"', '').trim(); // Sanitizes wrapping quotes for S3 SDK compliance
     }).timeout(const Duration(seconds: 60)); // Enforces full-operation timeout catching both addStream and header stalls
   }
   ```

3. **Persistent Upload State, File Fingerprinting & Crash Recovery:**
   - On upload initiation and every part completion, `MediaSharingService` records `{uploadId, r2Key, partSizeBytes, fileSizeBytes, fileLastModified, completedParts}` to local storage.
   - If the app process is terminated and restarted:
     ```dart
     // Verify file integrity before attempting resume
     if (file.lengthSync() != savedSession.fileSizeBytes ||
         file.lastModifiedSync() != savedSession.fileLastModified) {
       await abortUploadSession(savedSession.uploadId, savedSession.r2Key);
       return initiateFreshUpload();
     }
     ```
   - If file fingerprint matches, queries `media-share/list-parts` to verify uploaded parts on R2 before continuing with missing chunks.

4. **Sliding-Window JIT Part URLs & Worker Pool:**
   - Fetches presigned part URLs in sliding batches of **5–10 parts** to prevent URL expiration during slow mobile uploads.
   - Uploads via a worker pool of **2–3 concurrent PUT requests**.
   - Collects `UploadPartRecord(partNumber: n, etag: etag)` and ensures `parts.sort((a, b) => a.partNumber.compareTo(b.partNumber))` is performed before finalizing upload.

5. **Foreground Auto-Resume:**
   - Listens to `AppLifecycleState.resumed`: if an upload was in progress and interrupted while backgrounded, automatically resumes from the first missing part.

6. **Throttled Realtime Progress & Client Interpolation:**
   - Throttles outgoing `upload_progress` broadcasts to **once every 3.0–4.0 seconds** (or $\Delta \ge 5\%$) to preserve Realtime channel bandwidth for transport sync.
   - Receiving clients interpolate progress locally between broadcasts using reported `speedBytesPerSec` and `etaSeconds`.

7. **Broadcast-Suppressed 403 Refresher & Track Restoration:**
   - Provides `refreshStreamUrl(roomId)` to mint a replacement presigned GET URL without disrupting playback state if a player encounters an expired token.
   - Activates `_isRecovering403 = true` latch on the player to suppress outgoing sync broadcasts during re-open and seek.
   - Captures active subtitle track and audio track before reopening `media_kit` demuxer and restores them upon stream ready.

8. **Non-Disruptive Background Cache Downloader (Optional for Member):**
   - Downloads file chunks via HTTP `Range` requests into `getTemporaryDirectory()/pt_downloads/{roomId}/`.
   - If streaming while downloading, completing the download does **not** abruptly reload the player mid-stream (avoiding audio/video hitches). It persists the cached file path to `LocalMediaStore` for instant local playback on subsequent seeks, replays, or room rejoins.

```dart
enum MediaSharingState { none, requesting, uploading, ready, failed }

class MediaSharingProgress {
  final double fraction;        // 0.0 – 1.0
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSec;
  final Duration eta;
}

class UploadPartRecord {
  final int partNumber;
  final String etag;
  UploadPartRecord({required this.partNumber, required this.etag});
}
```

#### [NEW] `lib/rooms/media_sharing_cache.dart`

Manages local downloaded media cache hygiene:
- Stores files in `getTemporaryDirectory()/pt_downloads/{roomId}/` (or marks with `NSURLIsExcludedFromBackupKey` on iOS).
- Prunes files when rooms end or files exceed 7 days.
- Integrates with `LocalMediaStore` so cached downloads appear in local media lists seamlessly.

---

### 4. Client-Side Dart — Sync & Gate Integration

#### [MODIFY] [sync_logic.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/sync/sync_logic.dart)

Keep `memberSatisfiesGate` purely member-focused. Handle room upload state inside `evaluateGateState`:
```dart
/// Pure member gate evaluation.
bool memberSatisfiesGate(PresentMember member, RoomMedia media) {
  if (!member.isReady) return false;
  if (media.kind == .local && member.loadedFileName != media.name) return false;
  return true;
}

/// Room gate evaluation accounting for R2 media upload state.
GateState evaluateGateState({
  required bool hasPresenceSynced,
  required RoomMedia media,
  required List<PresentMember> members,
  Set<String> waived = const {},
  String mediaUploadState = 'none',
}) {
  if (!hasPresenceSynced) return .indeterminate;
  if (!media.isSet) return .closed;
  if (mediaUploadState == 'uploading') return .closed; // Blocks transport room-wide
  if (members.isEmpty) return .indeterminate;
  return members.every((m) => memberClearsGate(m, media, waived)) ? .open : .closed;
}
```

#### [MODIFY] [sync_service.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/sync/sync_service.dart)

Add media sharing broadcast methods and late-joiner auto-waiver handling:
- **Late Joiner Auto-Waiver:** When a member joins a live room that is already playing (`roomPlaying == true`) with shared media `ready`, the authority client automatically adds the new member to `_waived` temporarily until they emit `ReadyStatus.ready`. This guarantees `evaluateGateState` does not drop to `.closed` and prevents unwanted room-wide pauses for existing watchers.
- `broadcastUploadProgress(...)` (Host only, throttled $\ge 3.0\text{s}$).
- `broadcastSharingToggled(...)` (Host only).

#### [MODIFY] [sync_events.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/sync/sync_events.dart)

Add media sharing event types:
```dart
static const String uploadProgress = 'upload_progress';
static const String sharingToggled = 'sharing_toggled';
```

New event payloads:
- `UploadProgressEvent` — `{ fraction, speedBps, etaSeconds, state }` (Broadcast by host during upload, throttled $\ge 3.0\text{ s}$).
- `SharingToggledEvent` — `{ enabled, fileName, fileSize, uploadState }` (Broadcast on toggle on/off).

---

### 5. Client-Side Dart — Entitlement & Room Models

#### [MODIFY] [entitlement_service.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/profile/entitlement_service.dart)

Add to `TierLimits`:
```dart
final String mediaSharing;           // 'none', 'limited', 'full'
final int mediaSharingWeeklyBytes;   // 0 = unlimited
bool get canShareMedia => mediaSharing != 'none';
bool get hasUnlimitedSharing => mediaSharing == 'full';
```

#### [MODIFY] [room_models.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/rooms/room_models.dart)

Add to `Room`:
```dart
final int? mediaFileSize;
final String? mediaR2Key;
final String? mediaUploadId;
final String mediaUploadState;       // 'none', 'uploading', 'ready', 'failed'
final String mediaSharingLevel;      // 'none', 'limited', 'full'
```

Add to `RoomErrorCode`:
```dart
activeUploadInProgress('active_upload_in_progress', "You already have another file upload in progress."),
uploadQuotaExceeded('upload_quota_exceeded', "You've reached your weekly sharing quota (2.5 GB). Upgrade to Premium for unlimited sharing."),
uploadCooldownActive('upload_cooldown_active', "Uploads are temporarily cooling down. Please try again in a few minutes."),
mediaSharingDisabled('media_sharing_disabled', "Media sharing is temporarily undergoing maintenance.");
```

---

### 6. Client-Side Dart — Room Screen UI & User Flows

#### [MODIFY] [room_screen.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/rooms/room_screen.dart)

#### A. Clean Stream Handling, Network Watchdog & 403 Auto-Renewal:
Add `_adoptRemoteStream({required String streamUrl, required String name, Duration? seekTo})`:
- Opens `widget.player.open(Media(streamUrl, start: seekTo), play: false)`.
- Sets `_localFileName = name` (satisfies `memberSatisfiesGate` without executing local filesystem checks).
- **Network Load Watchdog:** Arms a 45-second watchdog for remote network streams (vs 15s for local files) to allow header/moov buffering over high-latency links without false "stalled" alerts.
- **Broadcast-Suppressed 403 Recovery & Track Restoration:**
  - Subscribes to `widget.player.stream.error` to detect network / HTTP 403 token expiration on remote streams.
  ```dart
  void _setupPlayerErrorListener() {
    _playerErrorSub = widget.player.stream.error.listen((error) {
      if (_isRemoteStream && !_isRecovering403 && _isStreamAuthOrNetworkError(error)) {
        _recoverStream403();
      }
    });
  }

  Future<void> _recoverStream403() async {
    final heldSubtitle = widget.player.state.track.subtitle;
    final heldAudio = widget.player.state.track.audio;
    _isRecovering403 = true;
    try {
      final freshUrl = await MediaSharingService.instance.refreshStreamUrl(roomId);
      await widget.player.open(Media(freshUrl, start: heldPosition), play: wasPlaying);
      if (heldSubtitle.id != 'auto') await widget.player.setSubtitleTrack(heldSubtitle);
      if (heldAudio.id != 'auto') await widget.player.setAudioTrack(heldAudio);
    } finally {
      _isRecovering403 = false;
    }
  }
  ```
- Bypasses local `LocalMediaStore.record` unless downloaded.

#### B. Subtitle & Audio Track Handling:
- Embedded subtitle tracks and audio tracks within container formats (`.mkv`, `.mp4`) stream and render natively through `media_kit`.
- `ChooserDialog<SubtitleTrack>` and `ChooserDialog<AudioTrack>` work automatically with streamed media.
- Sidecar `.srt` files outside the video container are not uploaded to R2; host upload confirmation includes a helper note: *"Embedded subtitle tracks in MKV/MP4 stream automatically. External .srt files are not uploaded."*

#### C. Host Flow (Sharing a Local File):
1. **Toggle Visibility:** Visible in topbar when user is host, mode is `.local`, a local file is loaded, and room `mediaSharingLevel != 'none'`.
2. **Toggle ON:**
   - Shows confirmation dialog with file name, file size, remaining weekly quota, cooldown warning (if any), and subtitle guidance note.
   - Acquires screen wake-lock (`WakelockPlus.enable()`) to prevent sleep during upload.
   - Calls `media-share/initiate` Edge Function and begins multipart upload.
   - Broadcasts `sharing_toggled { enabled: true }`.
3. **Upload Progress:** Determinate progress bar in topbar showing speed and ETA. Members see upload progress banner with dead-reckoning animation.
4. **Upload Complete:** Toast notification "File uploaded — members can now play or download." Room state updates to `ready`.
5. **Toggle OFF:** Confirmation dialog "Stop sharing? Shared file will be deleted from cloud." On confirm, calls `media-share/abort` / `clear_media_sharing`, releases wake-lock.
6. **File Switch Lock:** If host attempts to pick another video while sharing is active, displays a snackbar: "Turn off file sharing first to switch files."

#### D. Member Flow (Instant Stream + Optional Download):
1. **During Host Upload:** Readiness overlay suppresses file-picker prompt and displays: *"{hostName} is sharing {fileName}… ({progress}%, ~{eta} left)"*. Members can chat and voice call freely.
2. **When Upload Completes (`media_upload_state == 'ready'`):**
   - Shows action prompt with file size and estimated stream bitrate (e.g. `1080p · 2.4 GB (~4.5 Mbps)`), calculating bitrate only when probed duration is available (`media_duration_ms > 0`):
     - **"Play Now (Stream)"** *(Default)*: Fetches presigned stream URL from `media-share/download-url`, calls `_adoptRemoteStream(streamUrl, fileName)`. Readiness updates to `ready` immediately (0s wait, 0 GB disk).
     - **"Download to Device"**: Begins background download to cache. If the member is already streaming, completion records to `LocalMediaStore` without interrupting active playback (no mid-stream reload stutter); if the player was idle, it switches to the local file upon completion. (Highlighted with *"Recommended for high-bitrate video"* if calculated stream bitrate $> 15\text{ Mbps}$).
3. **Late Joiner Auto-Stream:**
   - If a member joins when the room is already live and playing with shared media, the app skips the modal prompt, auto-streams immediately, and adopts room position without triggering a room-wide pause gate transition for existing watchers.
   - A manual "Download to device" option remains available in the room menu.
4. **Gate Synchronization:**
   - Members streaming directly reach `ReadyStatus.ready` in seconds.
   - Host and members enter synchronized playback seamlessly.

---

### 7. UI Widgets

#### [NEW] `lib/rooms/widgets/media_sharing_toggle.dart`
Topbar icon button reflecting states: `off`, `uploading` (with spinner), `ready` (cloud checkmark), and `failed`.

#### [NEW] `lib/rooms/widgets/media_sharing_prompt_dialog.dart`
Member dialog on upload completion offering instant streaming vs background download, with file size, estimated stream bitrate (with duration fallback), and bandwidth recommendation.

#### [NEW] `lib/rooms/widgets/sharing_progress_indicator.dart`
Reusable progress bar displaying percentage, transfer speed (e.g., `14.2 MB/s`), and ETA, with smooth client-side dead-reckoning interpolation.

#### [MODIFY] [readiness_overlay.dart](file:///Users/shubham/Projects/Personal/playtogether/lib/rooms/widgets/readiness_overlay.dart)
Update overlay to handle upload state:
- If `mediaUploadState == 'uploading'`, renders a shared file upload banner with progress bar and ETA, suppressing the "Locate your copy" button.

---

### 8. Analytics Events & Diagnostics

Adhering strictly to the **human-initiated analytics doctrine** (`CLAUDE.md`), product events are logged only when triggered by human actions. Lifecycle/recovery transitions use `trace(category: 'media')`.

| Event | Properties | Type | Description |
|---|---|---|---|
| `media_sharing_toggled` | `room_id`, `enabled`, `file_size`, `tier` | Product (`Analytics.track`) | Host toggles sharing ON/OFF |
| `media_upload_started` | `room_id`, `file_size` | Product (`Analytics.track`) | Host upload starts |
| `media_stream_started` | `room_id`, `file_size` | Product (`Analytics.track`) | Member selects "Play Now (Stream)" |
| `media_download_started` | `room_id`, `file_size` | Product (`Analytics.track`) | Member selects "Download to Device" |
| `media_upload_completed` | `room_id`, `duration_seconds` | Diagnostic (`trace`) | Multipart upload finalized |
| `media_upload_failed` | `room_id`, `error`, `bytes_uploaded` | Diagnostic (`reportNonFatal`) | Upload error |
| `media_stream_renewed_403` | `room_id` | Diagnostic (`trace`) | Presigned URL refreshed on seek |

---

### 9. Edge Cases & Production Hardening

| Scenario | Mitigation |
|---|---|
| **Files larger than 5 GB** | S3 Multipart Upload handles files up to 10 GB (and beyond) seamlessly. |
| **Files smaller than 5 MB** | Part sizing logic uploads files $\le 10\text{ MB}$ as a single part (Part 1) to satisfy S3 minimum chunk bounds. |
| **Network drop / App crash mid-upload** | Client records uploaded part ETags, `fileSizeBytes`, and `fileLastModified` in `LocalMediaStore`; validates file modification timestamp on restart and queries `media-share/list-parts` to resume without restarting from 0%. |
| **Empty parts list on initial upload** | `media-share/list-parts` safely defaults to `(response.Parts ?? []).map(...)` if AWS SDK returns undefined parts. |
| **SigV4 header mismatch on part PUTs** | Client avoids setting ad-hoc un-signed `Content-Type` headers in `HttpClientRequest`, relying solely on `request.contentLength = chunkSizeBytes`. |
| **Single-subscription stream retries** | `createChunkStream(partNumber)` invokes `file.openRead(startOffset, endOffset)` freshly on each part attempt/retry to prevent using an exhausted stream. |
| **Chunk socket hangs on flaky networks** | Chunk upload requests wrap the entire part upload future in an explicit 60s timeout via `uploadPartFuture.timeout(const Duration(seconds: 60))`. |
| **Same-room re-upload orphan leak** | `request_upload_slot` checks if `v_room.media_upload_id` exists and is distinct from `p_upload_id`, pushing old upload sessions to `pending_r2_deletions` before updating `rooms`. |
| **Incomplete upload orphan leak on room expiry** | Edge Function persists `media_r2_key` and `media_upload_id` to `rooms` at upload initiation; `retire_room` enqueues them into `pending_r2_deletions` immediately. |
| **Dart slicing boundary** | `file.openRead(startOffset, min(startOffset + partSizeBytes, totalFileSize))` uses Dart's exclusive end offset correctly. |
| **S3 411 Length Required** | `request.contentLength = chunkSizeBytes` is explicitly set before calling `request.addStream` to avoid chunked transfer rejection. |
| **Service role user ID context & RPC boundary** | `request_upload_slot`, `set_media_upload_state`, and `record_upload_bytes` are granted strictly to `service_role`. Edge Function extracts verified `p_user_id` from JWT. |
| **Unicode & Special Character Filenames** | Presigned download URLs format `ResponseContentDisposition` with RFC 5987 (`filename*=UTF-8''...`) to prevent S3 signature errors. |
| **Dormant / Persistent room resume** | `retire_room` enqueues R2 key/upload ID into `pending_r2_deletions` and resets `media_r2_key = null`, `media_upload_id = null`, `media_upload_state = 'none'` on `rooms` so resumed rooms don't reference purged media. |
| **Stale host lock after crash / app kill** | `request_upload_slot` auto-clears stale `active_upload_room_id` if previous room is not live, upload state is not uploading, caller is no longer host, or lock is $>30\text{m}$ old. |
| **Media switch while sharing is active** | `set_room_media` RPC automatically enqueues old `(media_r2_key, media_upload_id)` into `pending_r2_deletions` and resets upload state. |
| **Stream URL expires during marathon (>6h)** | Presigned download URL is minted with TTL matching remaining room duration (up to 24h). `player.stream.error` listener triggers 403 recovery with broadcast suppression. |
| **Track selection loss during 403 recovery** | Active subtitle and audio tracks are captured before `player.open()` and restored on stream ready. |
| **0-second seek flash on stream start/recovery** | `_adoptRemoteStream` passes `Media(streamUrl, start: heldPosition)` directly to `media_kit` demuxer. |
| **Host succession mid-upload or mid-share** | Acting host inherits authority to call `clear_media_sharing` to reset stuck upload states or purge cloud objects; lock is cleared by room ID. |
| **S3 ETag formatting & Part ordering** | Client reads case-insensitive `HttpHeaders.etagHeader`, strips wrapping quotes, and strictly sorts the parts array ascending before `CompleteMultipartUploadCommand`. |
| **Low RAM devices during upload** | Chunks are streamed directly from `File.openRead` into the HTTP request body stream without loading entire chunks into RAM. |
| **Host disconnects / room ends** | `retire_room` enqueues R2 key and upload ID into `pending_r2_deletions`. `cleanup-r2` deletes object or aborts multipart upload within 5 minutes. 24-hour bucket lifecycle rule catches any edge drops. |
| **App backgrounded on mobile** | App acquires `WakelockPlus` during upload. When resumed (`AppLifecycleState.resumed`), `MediaSharingService` auto-resumes remaining parts. |
| **Slow mobile upload connection** | Part URLs are fetched just-in-time in sliding batches of 5–10 parts, preventing 30-minute part URL expiration. |
| **Concurrent upload quota race** | Postgres `request_upload_slot` and `record_upload_bytes` use `FOR UPDATE` row locks on `profiles` to prevent double-spending. |
| **Non-FastStart MP4 containers & Network buffering** | Range requests seek to the end of the file to read the `moov` atom. Network watchdog is set to 45s (vs 15s disk) to prevent false stall alerts. |
| **Sidecar subtitles vs embedded container tracks** | MKV/MP4 embedded subtitle tracks stream natively; external `.srt` sidecars are not uploaded to R2 (clarified in UI). |
| **Background download completion during streaming** | Completing an offline download while streaming saves to `LocalMediaStore` without reloading the player mid-playback, preventing 100-200ms audio hitches. |
| **Late joiners to active room** | Members joining an active streaming room auto-stream immediately with automatic temporary gate waiver, without blocking dialogs or pausing active room playback. |

---

### 10. Dependencies Summary

**Dart Dependencies (`pubspec.yaml`):**
- `storage_space` — for querying available disk space if a member explicitly opts to download offline.
- `wakelock_plus` — to prevent device sleep during active uploads.
- *(No AWS/S3 SDK packages added to Flutter client)*.

**Edge Function Dependencies:**
- `@aws-sdk/client-s3`
- `@aws-sdk/s3-request-presigner`

---

## Verification Plan

### Automated Tests
1. **Dart Unit Tests (`fvm flutter test`):**
   - `test/media_sharing_service_test.dart` — Multipart chunk slicing (exclusive offsets), explicit `contentLength`, SigV4 header neutrality, part retry logic, crash resume persistence, progress throttling, cooldown handling, part sorting & quote stripping, track preservation during 403 recovery.
   - `test/media_sharing_cache_test.dart` — Cache directory cleanup, TTL expiration, backup attribute verification.
   - `test/sync/sync_logic_test.dart` — Gate evaluation under `mediaUploadState == 'uploading'`, late-joiner auto-stream readiness with temporary waiver without transport pauses.
2. **Database pgTAP Tests (`supabase test db`):**
   - `supabase/tests/media_sharing_test.sql` — Host-only permissions on upload state RPCs, single active upload concurrency lock with multi-factor auto-healing, same-room re-upload orphan cleanup in `pending_r2_deletions`, grace window evaluation on cancels, quota deduction on completion, `pending_r2_deletions` insertion on `set_room_media` switch and `retire_room` with `media_upload_id`, dormant room media column resets, `create_room` level inheritance, `list_my_rooms` column return & grants, tightened `rooms_media_shape_chk` constraint enforcement.

### Manual Verification
- **Host Upload & Direct Stream**: Host uploads 500 MB video $\rightarrow$ Member selects "Play Now" $\rightarrow$ Player starts instantly from R2 stream $\rightarrow$ Synchronized playback verified.
- **Resumable Upload Verification**: Host starts 1 GB upload $\rightarrow$ Toggle airplane mode / terminate app at 40% $\rightarrow$ Re-open app $\rightarrow$ Verify upload resumes from 40% using local state & `list-parts` without restarting from 0%.
- **Readiness Gate Integration**: Host starts upload $\rightarrow$ Verify members see upload banner rather than "Locate your copy" $\rightarrow$ Upload finishes $\rightarrow$ Verify member readiness transitions to ready on stream start.
- **Late Joiner Verification**: Start playback with shared media $\rightarrow$ Join from second device $\rightarrow$ Verify late joiner immediately streams and adopts room position without blocking modals or pausing active playback.
- **Media Switch Cleanup**: Host uploads file $\rightarrow$ Host switches to YouTube video $\rightarrow$ Verify R2 key and upload ID are enqueued in `pending_r2_deletions` and upload state is reset.
- **Offline Download**: Member selects "Download to Device" $\rightarrow$ File downloads with progress $\rightarrow$ Player switches to local cached file upon completion.
- **Dormant Room Cleanup**: End a room with `dormant_hours > 0` $\rightarrow$ Verify R2 object/upload session is queued in `pending_r2_deletions`, `rooms.media_upload_state` resets to `'none'`, and `cleanup-r2` purges the file.
