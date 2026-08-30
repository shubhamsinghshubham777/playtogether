---
description: Supabase RLS policies, RPC invariants (create_room, join_room, end_room, delete_room), tier limits, Paddle webhook processing, and pgTAP testing.
trigger: model_decision
---


# Backend, Database & Entitlements

Guidance for working with Supabase (`supabase/`), database RPCs/RLS, tier entitlements, Paddle billing, and pgTAP testing.

## 1. Database & Supabase Architecture (`supabase/`)

### Core Schema & RLS
- **`profiles`**: Auto-created on signup; anonymous guests get `Guest-xxxx`.
- **`rooms`**: `code`, `expires_at`, `ended_at`, `media_kind`, `media_name`, `media_position_ms`, `transport_lock`.
  - **RLS Policy**: Must be membership *or* ownership (`using (is_room_member(id) or is_room_owner(id))`), enabling room creators who left to still view their blocking live room from the lobby.
- **`room_members`**: `role` (`host` or `member`), `joined_at`.
- **`messages`**: Persisted room chat; wiped upon room retirement/expiry.
- **Realtime Authorization**: Room channels are private channels (`room:<id>`) authorized via `realtime.messages` policies.

### RPC Invariants (`security definer`)
- **`create_room`**: Generates 6-char code; denormalizes caps from the **host's** tier.
- **`join_room`**: Idempotent for existing members. If a room is hostless (empty), it adopts the next joining member as host (tier-blind; prevents demotion upon re-entry).
- **`leave_room`**: Host succession passes to the earliest-joined remaining member.
- **`end_room`**: Allowed for acting host AND room creator; routes through `retire_room`.
- **`delete_room`**: Restricted to **room creator only** (`created_by`), never acting host. Calls `announce_room_ended` to broadcast `room_ended` over Realtime before deletion.
- **`list_my_rooms`**: Lists rooms owned OR joined (`is_member` and `is_owner`). When modifying its return type, you must drop the function, recreate it, and **re-`grant execute ... to authenticated`**.
- **`get_server_time`**: Used via `RoomService.serverNow` for clock-skew-free countdowns.

---

## 2. Entitlements & Room Lifecycle

Three tiers: `guest` / `free` / `premium`.

- **Limits are config**: Stored in `tier_limits` table. `effective_tier(uid)` is `guest` (anonymous), `premium` (active subscription), else `free`.
- **Host owns room properties**: Joiners experience the host's room limits and AV capabilities.
- **Expiry parks rooms**: `room_state` is `live` / `dormant` / `expired`. `sweep_rooms` cron drives transitions through `retire_room` (`dormant_hours = 0` for guests -> immediate deletion; persistent rooms for premium).
- **Extending rooms**: `extend_room` branches on tier config (`max_total_session_minutes`, `free_extension_minutes`), not hardcoded tier strings.
- **T-5 Expiry Banner**: Must NOT auto-dismiss for the host (it is the only affordance to extend/save the session). Auto-dismisses for members.
- **Crown & Badges**: Visible badges (`PremiumCrown`, `PTAvatar.premium`) are resolved via `room_member_tiers(p_room_id)` RPC (single roundtrip, membership-gated). Never use presence self-reports for entitlement claims.

---

## 3. Billing & Subscriptions (Paddle)

- **Paddle Checkout**: Managed via `@paddle/paddle-js` on the web portal (`website/`).
- **Webhook Processing (`website/app/api/paddle/webhook/route.ts`)**:
  - HMAC-SHA256 signature verification via `@paddle/paddle-node-sdk`.
  - **Deduplication**: Checks whether `status`, `current_period_end`, and `tier` are identical before issuing DB updates to avoid redundant writes and Realtime channel spam.
- **Realtime Subscriptions**: `subscriptions` table is published to Realtime. `EntitlementService` (`lib/profile/entitlement_service.dart`) listens to `public:subscriptions:$userId` Postgres changes and debounces reload (200 ms).
- **Debug Grants**: In local debug mode, use `debug_grant_premium(p_months)` RPC or `EntitlementService.instance.debugGrantPremium()`.

---

## 4. pgTAP Testing (`supabase/tests/`)

- Run tests with: `supabase start && supabase test db`
- **Transaction Rollback**: Each test file runs as an isolated transaction that rolls back automatically against the local stack.
- **Postgres `now()` Caveat**: `now()` evaluates to transaction-start time in Postgres; it does not advance across statements within a single test file. Assert against back-dated timestamps rather than sleeping.
