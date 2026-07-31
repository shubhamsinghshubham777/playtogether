# High-Value Test Suite — LIVING DOC

> **Read §0–§3 before touching any code.** Single source of truth for the
> test-suite initiative. Code is the source of truth; this doc is hypotheses.
>
> Any instance (Claude or human) picking this up:
> 1. Read §0 (mission), §1 (working agreement), §3 (audit board), and the LAST §8 entry.
> 2. Pick the first unchecked §3 item NOT gated on an unanswered §4 decision.
> 3. Grill the user (A/B/C options) before building anything gated.
> 4. Update §3 + append a §8 entry as the LAST step of every session.
> 5. At ~50–60% context usage, STOP and write a §8 handoff (template at top of §8).
> 6. When every §3 item is `[x]` and the user signs off, **delete this file**
>    (see §1 rule 9).

---

## 0. Mission & non-goals

**Mission.** The repo has zero tests. Build a test suite covering the
distributed-state logic that regresses silently and is expensive to debug in
production: sync event wire format, last-action-wins ordering, authority
election, the readiness gate, presence merging, and the server-side RPCs.
"Done" = all §3 items ticked, `fvm flutter test` green, `supabase test db`
green (if D lands), and the suite pins every invariant listed in §3 so a
future refactor that breaks one fails a test instead of a room.

**You are responsible for the success of this initiative.** Beyond the listed
items, audit your own area and take initiative to harden edge cases. Update
§3 when you discover new work.

### Non-goals (DO NOT do these)
- Widget/golden tests for RoomScreen or the room UI — heavy media_kit
  `Player`/webview coupling, low regression value per effort.
- Testing platform-channel code (Turnstile dialog, WebView2 runtime,
  window_manager fullscreen, deep links) — not reachable from `flutter test`.
- Testing the Python asset tools (`tool/*.py`) — they self-verify via SHA-256.
- Splash/animation timing, glass rendering, theme — guarded by CLAUDE.md, not
  worth brittle tests.
- Behavioral changes to production code. Tier 2/3 refactors must be pure
  extractions/seam injections with behavior identical; if a test reveals a
  real bug, record it in §8 and grill the user before fixing.

---

## 1. Working agreement

1. Code is the single source of truth. Verify every claim (including this
   doc's file:line references) against the tree before acting.
2. One in-progress §3 item at a time. Finish or hand off first.
3. Append-only §8. Never rewrite past entries.
4. At ~50–60% context usage, STOP and write a §8 handoff.
5. Update §3 + §8 as the LAST step of every session.
6. Dates are absolute (YYYY-MM-DD).
7. Grill before building — A/B/C options. Park unresolved calls in §4.
8. Repo-specific rules:
   - Always prefix `flutter`/`dart` with `fvm`. Test command: `fvm flutter test`.
   - No feature branches — work lands directly on `main`, ideally squashed to
     one commit per session/area.
   - No code comments, ever (user rule) — including in test files.
   - Dependency versions in pubspec.yaml are exact pins, no `^` ranges.
   - Dart dot-shorthand style (`_mode = .local`) — follow it in tests.
   - Pushing needs the personal account token (keychain work account 403s).
   - A `.env` must exist for `flutter test` to run (declared as asset).
9. **Cleanup on completion (this repo has no PR flow):** when every §3 item is
   `[x]`, the full suite is green, and the user has signed off — `git rm
   docs/high-value-tests.md` and commit (`chore: remove living doc — test
   suite shipped`). Migrate any durable notes (e.g. "how to run the pgTAP
   suite") into CLAUDE.md first. §8 history is process exhaust; let it die
   with the doc — git log is the durable record.

---

## 2. Architecture as-it-is (code-grounded — verify before trusting)

> Verified against `main` @ 1918df7 on 2026-07-31. Re-verify if the tree moved.
>
> **SUPERSEDED as of session 2** — this section describes the tree *before* the
> suite landed and is kept only as the record of what was surveyed. `test/` and
> `supabase/tests/` now exist, `SyncService` *is* constructible in a test, the
> event count was wrong (12 classes, not ~17), and the line numbers have all
> moved. See the last §8 entry, and CLAUDE.md for the durable shape.

Test-relevant shape:

- `lib/sync/sync_events.dart` (419 ln) — ~17 typed events, each with a
  `fromPayload` factory and serialization. Pure, no dependencies. Directly
  testable today.
- `lib/sync/sync_service.dart` (1236 ln) — the room sync orchestrator.
  Constructor takes media_kit `Player` + room/profile/role; reaches
  `Supabase.instance.client` via a getter (line ~116). NOT constructible in a
  test today. But its core decisions are pure functions of local state:
  `memberSatisfiesGate` (~178), `gateState` (~192), `_authorityAmong` (~969),
  `_shouldApply` (~1185), `_nextTimestamp` (~1174), presence merge in
  `_readPresence` (~485), reaction send throttle.
- `lib/rooms/room_models.dart` — `Room.fromJson`, `RoomMedia.isNewerThan`
  (line 119), `RoomMediaKind.fromWire`, `RoomErrorCode.fromError`. Pure.
- `lib/app_router.dart:24-27` — `roomPath` / `roomIdOfPath`. Pure.
- `lib/rooms/reactions.dart` — `kReactions` (line 15) allow-list; assets in
  `assets/emoji/*.json`; `tool/fetch_reaction_emoji.py` carries the manifest
  that must agree with `kReactions`.
- `supabase/migrations/` — 6 migrations; RPCs live in
  `20260724100000_multi_participant.sql` (create/join/leave/end_room),
  `20260726100000_room_media_transport_lock.sql` (set_room_media +
  `rooms_media_shape_chk`, set_transport_lock),
  `20260726110000_kick_and_ban.sql` (kick_member, room_bans).
- No `test/` directory exists. Dev deps: only `flutter_test`,
  `flutter_launcher_icons`, `flutter_lints`, `inno_bundle`.
- CI (`.github/workflows/`) is manual-trigger installer builds only — no test
  job anywhere.

### Key files (verified paths)

| Concern | File |
|---------|------|
| Sync events / wire format | `lib/sync/sync_events.dart` |
| Sync orchestrator (authority, gate, ordering) | `lib/sync/sync_service.dart` |
| Room/media/error models | `lib/rooms/room_models.dart` |
| Route helpers | `lib/app_router.dart` |
| Reaction allow-list | `lib/rooms/reactions.dart` |
| Emoji manifest (must match kReactions) | `tool/fetch_reaction_emoji.py` |
| RPCs: rooms/members/messages | `supabase/migrations/20260724100000_multi_participant.sql` |
| RPCs: media + transport lock | `supabase/migrations/20260726100000_room_media_transport_lock.sql` |
| RPCs: kick/ban | `supabase/migrations/20260726110000_kick_and_ban.sql` |
| Invariant documentation | `CLAUDE.md` (Sync layer / Readiness gate / Reactions sections) |

---

## 3. Audit board (tick as completed; ONE in-progress at a time)

> Legend: `[ ]` todo · `[~]` in progress · `[x]` done+verified ·
> `[?]` needs repro/logs · `[G]` blocked on a §4 decision.

### A — Tier 1: pure functions, no production-code changes
- [x] **A1. Sync event round-trips.** For every `SyncEvent` subtype in
  `lib/sync/sync_events.dart`: build → serialize → `fromPayload` → fields
  equal. Table-driven. Include `reason: 'gate'` on play/pause.
- [x] **A2. Malformed-payload tolerance.** Peer payloads are untrusted:
  missing fields, wrong types, nulls must not throw uncaught (verify actual
  current behavior first — pin what the code does, don't invent a spec).
- [x] **A3. Room models.** `Room.fromJson` (full + minimal rows),
  `RoomMediaKind.fromWire` unknown-value fallback, `RoomErrorCode.fromError`
  mapping table.
- [x] **A4. `RoomMedia.isNewerThan`** (`room_models.dart:119`): keyed on
  server `media_updated_at`; unset vs set, equal timestamps, skewed
  timestamps. This is the late-refetch-vs-broadcast clobber guard.
- [x] **A5. Route helpers.** `roomPath`/`roomIdOfPath` inverse property;
  non-room paths → null; ids containing odd characters.
- [x] **A6. Reactions allow-list contract.** `kReactions` entries each have a
  bundled `assets/emoji/<slug>.json`; list agrees with the manifest in
  `tool/fetch_reaction_emoji.py` (mirror the script's own cross-check);
  `_byEmoji` lookup rejects non-listed emoji.

### B — Tier 2: extract pure logic from SyncService, then test it
> Each B item = move the logic verbatim to `lib/sync/sync_logic.dart` (or
> similar), delegate from `SyncService`, behavior identical, then test.
- [x] **B1. Authority election** (`_authorityAmong`, sync_service.dart:969):
  host present wins; no host → earliest `joined_at`; user-id tie-break;
  requester-excluded election (host requesting own room's state → exactly one
  other responder; sole member → null/self semantics as coded).
- [x] **B2. Last-action-wins ordering** (`_shouldApply` ~1185 +
  `_nextTimestamp` ~1174): equal timestamp dropped, per-sender strictly
  increasing, same-millisecond play+seek pair both surviving (the
  `_playPause` synchronous-block invariant).
- [x] **B3. Gate evaluation.** `memberSatisfiesGate` (ready ≠ right file —
  name comparison), tri-state `gateState` (`indeterminate` before first
  presence sync — must render usable), blockers list, pause decision uses
  room-level `_roomPlaying` not own `isPlaying`, `_pausedByGate` cleared by
  human play/pause, held resume position dropped when self is the blocker.
- [x] **B4. Presence merge** (`_readPresence` ~485): multi-device same
  `user_id` collapses to one entry keeping the most-ready device — pins
  `ReadyStatus` declaration order as rank.
- [x] **B5. Reaction send throttle:** 250 ms cap coalesces rather than drops —
  last emoji of a burst always transmits; local echo never throttled.

### C — Tier 3: SyncService behavioral tests behind a fake channel
> Gated on Q2 (seam design) and Q3 (mocktail). Inject client/channel behind an
> interface; drive two simulated members.
- [x] **C1. Seam refactor.** Injectable channel abstraction; `SyncService`
  constructible without `Supabase.initialize` or a real `Player`.
- [x] **C2. Echo/loop prevention.** `_isApplyingRemoteAction` settle,
  self:false semantics, remote apply does not rebroadcast.
- [x] **C3. Late-joiner state sync.** Requester retries once after 2 s then
  assumes idle; `_checkSelfGateSatisfaction` re-requests on first-canonical-
  media-open edge; skipped when `_roomPlaying`/`_pausedByGate`/alone.
- [x] **C4. Reconnect teardown guard.** `_tearingDown` +
  `identical(channel, _channel)`: intentional `disconnect()` must not
  schedule a reconnect; drop does, with exponential backoff.
- [x] **C5. Reactions never touch playback.** Incoming reaction does not
  advance `_lastAppliedTimestamp`, never feeds `remoteActions`; gate-reason
  play/pause never raises attribution toasts; `state_response` never toasts.
- [x] **C6. Chat reload + fuzzy merge after reconnect** (no duplicate rows).

### D — Backend: pgTAP via `supabase test db`
> Gated on Q4 (local stack availability).
- [x] **D1. `join_room`:** ban check ordered BEFORE already-a-member return;
  8-member cap; expired/ended room rejected.
- [x] **D2. `leave_room`:** host succession → earliest joiner; last member
  leaving.
- [x] **D3. `create_room`:** guest one-live-room limit; 5–240 min duration
  clamp; code shape.
- [x] **D4. `kick_member` + `room_bans`:** host-only; ban row written;
  banned rejoin blocked.
- [x] **D5. `set_room_media`:** host-only + live-room enforced;
  `rooms_media_shape_chk` rejects cross-kind field mixes.

### E — Wiring
- [x] **E1. Test infrastructure.** Create `test/`, first smoke test,
  `fvm flutter test` green locally. Confirm `.env` asset requirement doesn't
  break `flutter test` (if it does, record the workaround in §8).
- [x] **E2. CI test job** (gated on Q1): `fvm`-less setup — CI uses Flutter
  3.44.8 directly; `analyze` + `test` on push.

---

## 4. Decisions (all resolved 2026-07-31, session 2)

- **Q1 → A.** New `.github/workflows/test.yaml`, on push/PR to main plus
  `workflow_dispatch`. Two jobs: `dart` (analyze + test) and `database`
  (pgTAP). Flutter pinned to 3.44.8 to match the installer workflows.
- **Q2 → A.** A narrow interface, widened slightly in practice: `SyncChannel`
  for the realtime surface **plus** `SyncBackend` bundling the other four
  server calls (membership, room refetch, chat load/insert) and a `SyncPlayer`
  port, all in `lib/sync/sync_backend.dart`. One seam = one fake. `SyncChannel`
  mirrors `RealtimeChannel`'s method names/arity so no call site changed.
- **Q3 → B.** Hand-rolled fakes (`test/sync/fakes.dart`, ~140 ln). No mocktail.
  `fake_async` 1.3.3 **was** added as an exact-pinned dev dep — it is virtual
  time, not mocking, was already in the transitive graph via `flutter_test`,
  and the alternative was real 2s/4s sleeps in the retry and backoff tests.
- **Q4 → A.** Docker was available once the user started it. Local stack +
  `supabase test db`; 5 files under `supabase/tests/`.

---

## 5. (reserved)

---

## 6. Test recipes

### R-1. Run the Dart suite
1. `fvm flutter test`
2. Expected: all green, no skips.

### R-2. Run the backend suite
1. `supabase start` (local stack; needs Docker running)
2. `supabase test db`
3. Expected: `Files=5, Tests=93 … Result: PASS`. Each file is one transaction
   that rolls back; no deployed project is touched.
4. If the db container is stale from an earlier session (`Exited (137)`),
   `supabase stop --no-backup && supabase start` first.
5. After mutating anything in the DB by hand, `supabase db reset` to put it
   back in step with `supabase/migrations`.

### R-3. Verify Tier 2 extraction changed nothing
1. `fvm flutter analyze` — clean.
2. `git diff` on `lib/sync/sync_service.dart` shows only delegation, no logic
   edits.
3. Manual: two-instance room sync smoke per CLAUDE.md
   (`./build/pt-instance-b.sh`) — hand the user this recipe; do not drive the
   GUI yourself (user rule).

---

## 7. Robustness patterns to adopt

- Table-driven tests for wire formats and mapping functions — one table row
  per event type/error code, not one test function each.
- Pin current behavior, don't invent specs: for tolerance tests (A2), assert
  what the code does today; if that behavior looks wrong, §8 + grill.
- Extracted logic takes plain values (lists of members, timestamps), never
  services — keeps Tier 2 tests dependency-free.
- Fake clocks/timestamps passed in, never `DateTime.now()` inside assertions.

---

## 8. Findings & handoff log (append-only — newest at BOTTOM)

### Handoff prompt template (copy, fill, paste for the next instance)
```
You are continuing the high-value-tests initiative. Read
docs/high-value-tests.md §0–§3 fully (code is the source of truth — verify
everything). Current branch: main. Last completed: <item>. In progress:
<item> — <exact state, files touched, what's left>. Blocked-on grills:
<Q#s + status>. Test status: <green/red, which suites>.
NEXT: <the single next action>. Follow §1 working agreement.
```

### 2026-07-31 (session 1) — initialized
- Scaffolded living doc from the plan proposed and discussed with the user
  this session. No code written yet (user instruction).
- Verified against main @ 1918df7: no `test/` dir; dev deps limited to
  flutter_test/lints/launcher_icons/inno_bundle; sync_service.dart line refs
  for `_authorityAmong` (969), `_shouldApply` (1185), `memberSatisfiesGate`
  (178), `gateState` (192); `RoomMedia.isNewerThan` (room_models.dart:119);
  `kReactions` (reactions.dart:15); 6 migrations present.
- §3 seeded: A1–A6 (pure, ungated), B1–B5 (extraction), C1–C6 (gated Q2/Q3),
  D1–D5 (gated Q4), E1 ungated, E2 gated Q1.
- §4 open: Q1 (CI), Q2 (Tier 3 seam), Q3 (mocktail), Q4 (local Supabase
  stack). None answered yet.
- NEXT: grill the user on Q1–Q4, then start E1 (test infra) followed by A1.

### 2026-07-31 (session 2) — everything shipped; awaiting sign-off to delete
- Grilled Q1–Q4 up front; all four answered (see §4). Docker was down at first,
  the user started it, so section D went ahead rather than being dropped.
- **All 24 §3 items are `[x]`.** `fvm flutter test` → 231 passing.
  `supabase test db` → 93 passing across 5 files. `fvm flutter analyze` clean.
- Files added: `test/{app_router,rooms/room_models,rooms/reactions}_test.dart`,
  `test/sync/{sync_events,sync_logic,sync_service}_test.dart`,
  `test/sync/fakes.dart`, `supabase/tests/0{1..5}_*.sql`,
  `.github/workflows/test.yaml`.
- Production code touched, delegation only: `lib/sync/sync_logic.dart` (new,
  extracted), `lib/sync/sync_backend.dart` (new, seam),
  `lib/sync/sync_service.dart` (−202/+69, no logic edits — R-3 step 2 verified),
  `lib/rooms/room_screen.dart` (two lines: wrap the player, call the extracted
  chat merge). Durable notes migrated into CLAUDE.md per §1 rule 9.

**Findings — behaviour pinned, none "fixed" (§0 non-goals):**
1. The "tolerant" event factories (`MediaSetEvent`, `ReactionEvent`) are
   **null-tolerant but not type-tolerant**: `payload['kind'] as String? ?? 'none'`
   throws on an int. My first draft asserted the opposite and failed — the code
   was right, the hypothesis wasn't. Combined with `_guard` a wrong-typed
   `media_set` is dropped whole, and the resubscribe refetch is what heals it.
2. `sync_events.dart` has **12 event classes, 15 type constants** — `room_ended`,
   `transport_lock` and `member_kicked` are built as raw maps inline. §2 said
   "~17 typed events"; that was wrong.
3. `RoomErrorCode.fromError` is a **substring scan in declaration order**, so a
   code that is a prefix of another would mis-map. None currently is, and there
   is now a test asserting that stays true.
4. `roomIdOfPath('/lobby/room/')` returns `''`, not null, and
   `/lobby/room/r1/extra` returns `'r1/extra'`. Harmless today (go_router
   matches before these are called); pinned so it is a decision, not a drift.
5. Mutation-checked rather than assumed — each of these was temporarily broken
   and the suite caught it: routing reactions through `_shouldApply` (1 failure),
   dropping the `_tearingDown`/`identical` reconnect guard (1 failure), and
   moving `join_room`'s ban check after the already-a-member return (1 failure,
   exactly the intended test). DB restored via `supabase db reset` afterwards.

**Gotchas worth keeping:**
- `flutter test` fails at "Failed to build asset bundle" with no `.env` — it is
  a declared asset. CI writes it from `ENV_FILE`; an empty secret still works.
- Postgres `now()` is transaction-time, so a pgTAP file cannot watch a timestamp
  advance between statements. Back-date the column yourself, then assert.
- `throws_ok(sql, '23514', 'desc')` reads the 3rd arg as the expected *message*,
  not the description — pass `null` for the message and use the 4-arg form.

- NEXT: user reviews and signs off, then §1 rule 9 — `git rm docs/high-value-tests.md`.
