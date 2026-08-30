# SyncTogether Web Portal

The official web application for [SyncTogether](https://synctogether.app) — featuring the marketing landing page, app downloads, release changelogs, FAQ and legal policies, Supabase authentication, and Paddle Merchant of Record (MoR) billing checkout & account management.

## Tech Stack

- **Framework**: [Next.js 15](https://nextjs.org/) (App Router) + React 19
- **Styling**: [Tailwind CSS v4](https://tailwindcss.com/) with dark violet glassmorphism tokens matching the Flutter app design system
- **Auth & Database**: [Supabase](https://supabase.com/) (`@supabase/ssr`) with PostgreSQL row-level security and Realtime subscriptions
- **Billing**: [Paddle Billing](https://developer.paddle.com/) Merchant of Record (`@paddle/paddle-js`, `@paddle/paddle-node-sdk`)
- **Testing**: Node.js built-in test runner (`node --test`) with TypeScript

## Getting Started

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment Variables

Copy `.env.example` to `.env.local`:

```bash
cp .env.example .env.local
```

Required environment variables:
- `NEXT_PUBLIC_SUPABASE_URL`: Supabase URL (e.g. `http://127.0.0.1:54321` for local dev or production project URL)
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: Supabase anon/publishable key
- `SUPABASE_SERVICE_ROLE_KEY`: Supabase service role secret (used securely by webhook handlers to update `subscriptions`)
- `NEXT_PUBLIC_PADDLE_CLIENT_TOKEN`: Paddle client-side token (`test_...` or `live_...`)
- `NEXT_PUBLIC_PADDLE_ENVIRONMENT`: `sandbox` for development, `production` for live
- `NEXT_PUBLIC_PADDLE_MONTHLY_PRICE_ID`: Paddle price ID for Monthly plan
- `NEXT_PUBLIC_PADDLE_ANNUAL_PRICE_ID`: Paddle price ID for Annual plan
- `PADDLE_API_KEY`: Paddle API secret key
- `PADDLE_WEBHOOK_SECRET_KEY`: Paddle notification webhook secret key (`pdl_ntfset_...`)

### 3. Run Development Server

```bash
npm run dev
```

Visit [http://localhost:3000](http://localhost:3000).

### 4. Run Tests

```bash
npm test
```

Runs the test suite in `tests/` (testing Paddle webhook signature validation, database write deduplication, and subscription lifecycle logic).

## Local Paddle Webhook Testing

Paddle webhooks can be forwarded to your local development server using [Hookdeck](https://hookdeck.com) or the [Paddle CLI](https://developer.paddle.com/tools/cli):

```bash
# Using Hookdeck
hookdeck listen 3000 synctogether-webhooks --path /api/paddle/webhook

# Using Paddle CLI
paddle webhook:listen --url http://localhost:3000/api/paddle/webhook
```

Copy the webhook secret provided by Hookdeck / Paddle into `PADDLE_WEBHOOK_SECRET_KEY` in `.env.local`.

## Key Routes & Architecture

### User-Facing Pages
- `/` — Homepage featuring interactive hero playback synchronizer and feature breakdown
- `/pricing` & `/premium` — Interactive plan selector, FAQ, and embedded Paddle Checkout overlay
- `/account` — Authenticated account overview, subscription status, renewal date, and cancellation action
- `/auth` & `/auth/callback` — Supabase Google OAuth and magic link authentication flows
- `/download` — Desktop installers for macOS (DMG) and Windows (Inno Setup)
- `/changelog` — Release history fetched directly from GitHub releases
- `/faq`, `/privacy`, `/terms`, `/refund` — Help center and compliance documentation

### API Route Handlers
- `POST /api/paddle/webhook` — Receives and verifies Paddle subscription webhooks (`subscription.created`, `subscription.updated`, `subscription.activated`, `subscription.canceled`, `subscription.past_due`, `subscription.paused`), applying write-deduplication before updating Supabase.
- `POST /api/paddle/cancel` — Authenticated endpoint allowing users to cancel their active subscription at period end.
- `GET /api/paddle/prices` — Real-time price query endpoint proxying Paddle Billing pricing.
- `GET /api/releases/latest` — Proxies GitHub release assets and metadata for downloads.
