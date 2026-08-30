<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## SyncTogether Web Portal Architecture & Guidelines

### Overview
This Next.js 15 application serves as the marketing site, downloads portal, legal documentation, authentication bridge, and Paddle Merchant of Record (MoR) subscription & account management portal for SyncTogether.

### Supabase SSR Patterns
- **Client Components**: Use `createClient()` from `lib/supabase/client.ts` (`createBrowserClient`).
- **Server Components & Route Handlers**: Use `createClient()` from `lib/supabase/server.ts` (`createServerClient` with `cookies()`).
- **Admin / Webhooks**: Use `createAdminClient()` from `lib/supabase/admin.ts` (`SUPABASE_SERVICE_ROLE_KEY`) only in secure server route handlers that require elevated database privileges (e.g. updating `subscriptions`).

### Paddle Billing Invariants
1. **Webhook Signature Verification**: Webhooks at `/api/paddle/webhook` must always verify the raw body against the `Paddle-Signature` header using `PADDLE_WEBHOOK_SECRET_KEY` and `@paddle/paddle-node-sdk`.
2. **Write Deduplication & Idempotency**: Prior to updating the `subscriptions` table, verify whether the incoming status, tier, and period end differ from the current database row (`tests/webhook_dedup.test.ts`). Avoid issuing redundant DB writes that trigger unnecessary Postgres realtime events on the Flutter clients.
3. **Cancellation Flow**: `/api/paddle/cancel` authenticates the caller via Supabase JWT, verifies subscription ownership, and requests cancellation at period end via the Paddle API.

### Design System & Styling
- Styled with Tailwind CSS v4 with dark violet glassmorphism tokens matching the Flutter app.
- Shared components in `components/`: `PTButton`, `GlassPanel`, `PlanCard`, `PricingTable`, `Header`, `Footer`, `HeroSyncSimulator`.

### Testing & Verification
- Unit test suite in `tests/` tests webhook signature verification, deduplication, and deactivation logic.
- Run tests with `npm test`.
