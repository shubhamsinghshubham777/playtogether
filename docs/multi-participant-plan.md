# PlayTogether — Multi-Participant Upgrade Plan

Status: **v2 — all open questions decided (§9), ready for implementation**
Scope: evolve the app from a single hardcoded 2-peer channel into an authenticated, room-based,
multi-participant watch-together app.

---

## 1. Target user flow

```
App launch
  └─ Session valid? ──no──► Login screen (Google, or "Continue as guest")
        │ yes
        ▼
      Lobby ──────────────► Profile settings (name + photo; email read-only)
        ├─ Create room (pick duration ≤ 240 min) ─► Room (player + chat + members)
        └─ Join room (code / invite link) ────────► Room
                                                      │
                                        room expires / host ends / user leaves
                                                      ▼
                                       Popup ("Room has ended") ─► back to Lobby
Session expiry / logout (any screen) ─► back to Login
```

New screens: **Login**, **Lobby**, **Profile**, **Room** (today's `PTVideoPlayer` becomes the
Room screen's body). The hardcoded user-picker dialog (`lib/username_dialog.dart` — a fixed
two-person "Who are you?" chooser) is **removed entirely**: identity now comes from the
authenticated account, and the display name from the profile.

---

## 2. Phase 0 — Prerequisites & infrastructure

### Supabase project configuration (dashboard / SQL, no app code)

1. **Enable auth providers**: Google OAuth and **anonymous sign-ins** (guest mode, §9.8) in
   Supabase Auth settings. Apple login is deferred (§9.9).
   - Google: OAuth client IDs per platform (Web client ID for Supabase; Android client with
     SHA-1 and iOS/macOS clients only when native mobile flows land).
   - Anonymous sign-ins have a default per-IP rate limit (~30/hour) — fine for guests.
2. **Redirect / deep-link scheme**: register a custom scheme, e.g. `playtogether://auth-callback`,
   in Supabase's allowed redirect URLs. Needed for the browser-based OAuth flow on
   Windows/Linux (and Android/iOS if we skip native SDKs, see Phase 1).
3. **Storage**: create an `avatars` bucket (public read, authenticated write, path-scoped
   `avatars/{user_id}.jpg`, size limit ~2 MB via bucket policy).
4. **Realtime authorization**: switch room channels to **private channels** so only room members
   can subscribe (RLS policies on `realtime.messages`, see Phase 3). Today anyone with the anon
   key can join `playtogether:default` — that must not survive this upgrade.
5. **pg_cron** extension enabled for room-expiry sweeps (Phase 5).

### Platform plumbing

- Deep links: `app_links` package; declare the scheme in `AndroidManifest.xml`, `Info.plist`
  (iOS + macOS), and Windows/Linux runner registration. Also used later for invite links.
- Keep dependency versions **exact-pinned** per repo convention; run everything through `fvm`.

### Database schema (single migration, `supabase/migrations/`)

```sql
-- Profiles: 1:1 with auth.users. Email mirrored for display; identity = auth.users.id.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,                         -- read-only mirror, never user-editable; null for guests
  is_guest boolean not null default false,
  display_name text not null check (char_length(display_name) between 1 and 40),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Trigger: auto-create profile row on signup. Google users: seed display_name/email from
-- OAuth metadata. Anonymous users: is_guest = true, display_name 'Guest-<4 chars>'.

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,          -- 6-char human join code, generated server-side
  name text not null default 'Watch party',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  duration_minutes int not null check (duration_minutes between 5 and 240),
  expires_at timestamptz not null,    -- created_at + duration_minutes, set by RPC
  ended_at timestamptz                -- set on expiry sweep or host "end room"
);

create table public.room_members (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('host', 'member')),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

-- Chat persistence (§9.5): history lives exactly as long as the room.
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  content text not null check (char_length(content) between 1 and 500),
  created_at timestamptz not null default now()
);
```

RLS (all four tables enabled):
- `profiles`: anyone authenticated can `select`; only `auth.uid() = id` can `update`, and a
  column-level grant (or trigger) blocks changes to `email`/`id`/`is_guest`. **Guests cannot
  update at all** (§9.8) — the policy also requires `is_guest = false`.
- `rooms`: members can `select`; creation only via `create_room` RPC (`security definer`) so
  the 240-minute cap, code generation, and `expires_at` are enforced server-side — never trust
  the client's clock or input. **Guest limit** (§9.8): if the caller is anonymous, creation is
  rejected while they still have a live room (`created_by = auth.uid() and ended_at is null
  and expires_at > now()`) — one room at a time, freed only by expiry or their explicit
  `end_room`.
- `room_members`: members of the same room can `select`; join only via `join_room(code)` RPC
  which validates the room exists, hasn't expired, and has fewer than **8 members** (§9.2).
- `messages`: room members can `select` and `insert` (with `sender_id = auth.uid()`); no
  client-side update/delete. Rows die with the room via cascade / expiry cleanup.
- `realtime.messages`: policy allowing broadcast/presence only where the topic matches
  `room:<id>` and the caller is in `room_members` for that room.

RPCs: `create_room(name, duration_minutes)`, `join_room(code)`, `leave_room(room_id)`,
`end_room(room_id)` (host only), and `get_server_time()` (or use the `Date` header) for
clock-skew-free countdowns. `leave_room` also performs **host succession** (§9.6): if the
departing member is the host, the remaining member with the earliest `joined_at` is promoted.

**Free-tier budget** (§9.7): development runs on the free Supabase tier for months, and the
design fits — 200 concurrent Realtime connections ≈ 25 full 8-member rooms live at once,
anonymous sign-ins and pg_cron are available on free, and 1 GB storage covers thousands of
512×512 avatars. Revisit before real launch (Pro adds connection headroom and daily backups).

---

## 3. Phase 1 — Authentication & session management

### New code

```
lib/auth/
  auth_service.dart      # thin wrapper over Supabase auth; exposes authStateStream, signIn*, signOut
  auth_gate.dart         # root widget: routes Login ↔ app based on session
  login_screen.dart      # Google + Apple buttons, error surface, loading state
```

### Sign-in flows per platform

**Google-only at launch** (§9.9), plus a "Continue as guest" button calling
`signInAnonymously()` (§9.8).

| Platform | Google |
|---|---|
| Windows / Linux (primary) | browser `signInWithOAuth` + deep link |
| macOS | browser `signInWithOAuth` + deep link |
| Android / iOS | browser flow initially; native `google_sign_in` → `signInWithIdToken` as polish |

The **primary user is on desktop**, so the browser `signInWithOAuth` + deep-link flow is the
first-class path: one code path that works on every platform — build and test it on
Windows/macOS/Linux first; native mobile SDK flows are later polish.

**Apple deferral caveat**: Apple's App Store mandates Sign in with Apple wherever third-party
login (Google) is offered on iOS — so an **iOS App Store release is blocked** until Apple
login is added. Desktop and Android distribution are unaffected.

**Guest sessions**: an anonymous session persists and refreshes like any other. If it's lost
(app data cleared), that guest identity — and any live room it hosts — is orphaned until the
expiry sweep cleans it up. Optional later: `linkIdentity()` upgrades a guest to a Google
account in place, keeping the same user id.

### Session lifecycle

- `supabase_flutter` already persists the session and auto-refreshes tokens; we only react to
  `onAuthStateChange`:
  - `signedIn` / `tokenRefreshed` → ensure profile loaded, show app.
  - `signedOut` → pop everything, show Login.
- **Session expiry**: when refresh fails (revoked token, long offline period), the SDK emits
  `signedOut` — same path as logout, so "throw back to login" is one code branch. Add a
  defensive check: any Supabase call returning `401`/`JWT expired` triggers `signOut()`.
- Logout button lives on Lobby and Profile screens. Logging out while in a room first calls
  `leave_room` and unsubscribes the channel.

### Changes to existing code

- `main.dart`: replace the user-picker bootstrap (`_UsernameSelectionScreen` +
  `_onUsernameSelected`) with `AuthGate`. `SyncService` is no longer created at startup — it
  becomes room-scoped (Phase 4).
- **Delete `lib/username_dialog.dart` in this phase.** It hardcodes the two users
  ("Reet"/"Shubh") and is the last remnant of the fixed-2-peer design. Until the profile
  screen lands (Phase 2), the display name shown to peers falls back to the OAuth account's
  name (`user_metadata['full_name']`) — no dialog needed in the interim.

---

## 4. Phase 2 — Profile & settings screen

```
lib/profile/
  profile_service.dart   # fetch/update profile, avatar upload to Storage
  profile_screen.dart    # avatar picker, display-name field, read-only email, logout, delete account
```

- **Editable**: `display_name`, avatar (pick via existing `fast_file_picker`, client-side
  downscale/crop to e.g. 512×512 JPEG, upload to `avatars/{uid}.jpg`, store public URL +
  cache-busting query param in `profiles.avatar_url`).
- **Read-only**: email — rendered as plain text with a lock affordance; enforced server-side
  by RLS/trigger, not just UI.
- On first login, if the OAuth provider gave no usable name, prompt once for a display name
  (replaces the old username dialog's job).
- **Guests** (§9.8): the profile screen shows the generated "Guest-xxxx" identity with name
  and photo editing disabled — there is no persistent user to edit. In place of the form,
  show a "Sign in with Google" prompt (optionally via `linkIdentity()`). Account deletion is
  hidden for guests too.
- **Account deletion** (required by both App Store and Play Store policies): "Delete account"
  button → confirm dialog → `security definer` RPC deletes `auth.users` row (cascades wipe
  profile/memberships) → local sign-out.

---

## 5. Phase 3 — Rooms (create / join / lobby)

```
lib/rooms/
  room_service.dart      # RPC calls, current-room state, member list stream
  lobby_screen.dart      # create-room card (name + duration slider 5–240 min), join-by-code field, profile entry point
  room_models.dart       # Room, RoomMember
```

- **Create**: duration picker capped at **240 min** in UI *and* by the DB check constraint.
  Default suggestion: 150 min. Creator becomes `host`.
- **Join**: 6-character code (unambiguous alphabet, no `0/O/1/I`) **and invite deep links
  from day one** (§9.3): `playtogether://join/<code>`. Both funnel into the same `join_room`
  RPC (expiry + 8-member cap enforced there). Room screen gets a "Copy invite link" button
  next to the code. Invite links compose with guest mode: a link recipient without an account
  taps "Continue as guest" and lands straight in the room.
- **Host succession** (§9.6): when the host leaves, `leave_room` promotes the earliest-joined
  remaining member. If the last member leaves, the room simply stays live until expiry
  (rejoinable by code) — no auto-end.
- **Chat persistence** (§9.5): messages are inserted into the `messages` table *and* fanned
  out over the Realtime channel; on room entry the client loads history from the table. This
  replaces `SyncService`'s in-memory `_chatHistory`. History dies with the room.
- **Channel naming**: `room:<room_id>` (private channel, membership enforced by Realtime RLS).
  The hardcoded `playtogether:default` and its `self: false` public channel die here.
- Room screen shows: member list with avatars + presence (green dot), room code (tap to copy),
  countdown to expiry, leave button; host additionally gets "end room".

---

## 6. Phase 4 — Multi-participant sync refactor

`SyncService` ([lib/sync/sync_service.dart](../lib/sync/sync_service.dart)) mostly generalizes
cleanly because everything is already broadcast-based, but several 2-peer assumptions must go:

1. **Room-scoped lifecycle**: `SyncService(player, room: Room, profile: Profile)` — created on
   room entry, disposed on leave. No more app-lifetime singleton.
2. **Presence → member list**: replace the boolean `peerOnlineStream`
   ([sync_service.dart:24-27](../lib/sync/sync_service.dart#L24-L27)) with
   `Stream<List<PresentMember>>` keyed by `user_id` (a user with two devices counts once).
   UI: member list panel instead of the single online/offline indicator.
3. **Identity in events**: `senderId` becomes the authenticated `user_id`; add `displayName`
   where the UI needs it (chat already carries `username` — rename to keep payloads honest).
4. **Late-joiner state sync at N>2**: today every loaded peer answers `state_request` and the
   joiner keeps only the first response ([sync_service.dart:253-256](../lib/sync/sync_service.dart#L253-L256)).
   With N peers that's N-1 redundant broadcasts. Fix: **only the authority answers** — the
   host if present, otherwise the earliest-joined present member (deterministic from presence
   data, no extra coordination). Fallback: if no response within 2 s, retry once, then assume
   idle room.
5. **Control model** (§9.1): **any member can control playback** — matches current
   egalitarian behavior; last-action-wins ordering
   ([sync_service.dart:295-307](../lib/sync/sync_service.dart#L295-L307)) already resolves
   races.
6. **Typing indicators**: track a *set* of typing user IDs with per-user timeouts, render
   "A, B are typing…".
7. **Drift correction** (new, matters more with N peers): host broadcasts a lightweight
   `position_sync` every 10 s while playing; members correct only if |drift| > 1.5 s. Keeps
   the seek-storm risk low while preventing slow divergence.
8. **Local-file mode caveat**: with N participants everyone must load the same file manually.
   Broadcast the file's name + duration on load; members whose loaded file mismatches get a
   warning banner. (True file verification/streaming is out of scope.)

---

## 7. Phase 5 — Room expiry & eviction

Layered enforcement — client UX, realtime kick, and server truth:

1. **Server truth**: `rooms.expires_at` set by the `create_room` RPC. A **pg_cron** job every
   minute sets `ended_at` on expired rooms. All join/read RLS checks `expires_at > now() and
   ended_at is null`, so an expired room is unusable even if a client's clock lies.
2. **Client countdown**: on room entry, fetch server time once, compute offset, and run a
   local ticker against `expires_at`. Show the countdown in the room UI; at T-5 min show a
   warning snackbar.
3. **Eviction**: when the countdown hits zero (or a `room_ended` broadcast arrives — sent by
   the host's client at expiry and by `end_room`): pause playback, unsubscribe the channel,
   show a **blocking popup** — "This room has ended" — whose only action returns to the Lobby.
4. **Edge cases**: member offline at expiry → eviction check also runs on app resume and on
   every failed RPC with an "room ended" error; rejoin attempts fail at `join_room` with a
   clear message.

**No extension** (§9.4): expiry is absolutely fixed at creation. There is no extend RPC, and
the countdown UI must not hint otherwise — the T-5-min warning tells members to wrap up (or
create a follow-up room after this one ends).

---

## 8. Phase 6 — Production hardening (recommended, prioritized)

**P0 — needed before any public release**
- **Account deletion** in-app (store policy; covered in Phase 2).
- **Privacy policy + terms** URLs (store requirement once auth/PII exists) and a licenses page.
- **Private Realtime channels + RLS everywhere** (Phase 0/3) — without this, any client with
  the publishable key can spy on or control any room.
- **Error/crash reporting**: `sentry_flutter` (works on all 5 target platforms) with user-id
  scrubbing; wire `runZonedGuarded` + `FlutterError.onError`.
- **Member cap per room: 8** (§9.2) enforced in `join_room` — Supabase Realtime message fan-out
  is O(N²) with everyone broadcasting; the cap keeps free-tier limits (§9.7) and sync sanity.
- **Reconnection handling**: Realtime drops on network change; on `channelError`/`closed`,
  auto-resubscribe with backoff, re-request state, show a "reconnecting…" banner.

*(Invite deep links and chat persistence were promoted from this list into Phase 3 — both are
day-one features per §9.3/§9.5.)*

**P1 — soon after**
- **Kick/ban** by host (removes membership row; Realtime RLS then blocks the channel). Worth
  pairing with a "no guests" room toggle, since anonymous users are the likeliest abuse vector.
- **Basic abuse controls**: chat length limits, simple rate limiting in RPCs.
- **CI**: add `flutter analyze` + (new) widget/unit tests as a PR gate; keep installer builds
  manual. Start a `test/` suite with the sync-protocol logic (event serialization,
  `_shouldApply` ordering, expiry math) which is pure Dart and cheap to test.

**P2 — nice to have**
- Emoji reactions overlay during playback; "everyone ready" check before start.
- Room history ("recent rooms") on the Lobby.
- Analytics (PostHog/self-hosted; keep it minimal and disclosed).
- Localization scaffolding (`flutter_intl`) before strings multiply.

### New dependencies (exact pins, versions to be resolved at implementation time)

`app_links` (OAuth callback + invite links), `go_router` (Login/Lobby/Room/Profile routing),
`image` (avatar downscale), `sentry_flutter` (P0 hardening). `google_sign_in` only when the
native mobile flows land — the desktop-first browser OAuth flow doesn't need it.
`sign_in_with_apple` is deferred along with Apple login (§9.9).

---

## 9. Decisions (locked 2026-07-24)

| # | Topic | Decision |
|---|---|---|
| 1 | Playback control | **Everyone** — any member can play/pause/seek |
| 2 | Member cap | **8 per room**, enforced in `join_room` |
| 3 | Join mechanism | **Codes + invite deep links from day one** |
| 4 | Room extension | **None** — expiry absolutely fixed at creation |
| 5 | Chat persistence | **Per-room `messages` table until expiry**; late joiners load history |
| 6 | Host leaves | **Auto-promote the earliest-joined remaining member** |
| 7 | Supabase tier | **Free tier during the dev months**; design within free limits, Pro before real launch |
| 8 | Guest mode | **Yes**, via anonymous sign-in, with hard limits: at most **1 live room** (a new one only after the previous expires or the guest explicitly ends it), **no profile editing** |
| 9 | Apple login | **Deferred** — Google-only on every platform; **primary user is desktop**. iOS App Store release stays blocked until Apple login lands |

---

## 10. Suggested implementation order & risk notes

| Order | Phase | Risk | Notes |
|---|---|---|---|
| 1 | 0 Infra + schema | Medium | OAuth console setup is fiddly; do it first, it gates everything |
| 2 | 1 Auth + session | Medium | Browser-OAuth-everywhere first; native SDKs later |
| 3 | 2 Profile | Low | Straightforward CRUD + Storage |
| 4 | 3 Rooms | Medium | RLS + private channels are the part to get right, test with 3 devices |
| 5 | 4 Sync refactor | **High** | Most behavioral risk; keep the event protocol, change identity/presence/state-sync |
| 6 | 5 Expiry | Low | Mostly server-side; client popup is simple |
| 7 | 6 Hardening | — | P0 items before any public build |

Biggest single risk: **Phase 4** touches the delicate echo/loop-prevention and dialog-dismissal
logic in `PTVideoPlayer`. Mitigation: land Phases 1–3 without touching the player at all (rooms
can initially still be 2-peer under the hood), then refactor sync in isolation with a
3-device manual test script.
