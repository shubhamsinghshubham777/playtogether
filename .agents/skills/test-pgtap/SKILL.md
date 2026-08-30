---
name: test-pgtap
description: >-
  Run, debug, and author pgTAP database tests for SyncTogether's Supabase backend. Use when the user asks to "run database tests", "test postgres functions", "run pgTAP", "verify supabase RPCs", or run `supabase test db`.
---

# pgTAP Database Testing

SyncTogether uses pgTAP for automated SQL and RPC testing against a local Supabase PostgreSQL container.

## Running Tests

Ensure Docker and the local Supabase stack are running:

```bash
supabase start && supabase test db
```

To run a specific test file:
```bash
supabase test db supabase/tests/database/01_rooms_test.sql
```

## pgTAP Authoring Guidelines

1. **Transaction Isolation**:
   Every test file runs inside an individual transaction that rolls back automatically. It will never mutate local development data permanently.

2. **Transaction Time vs. Wall Clock (`now()`)**:
   `now()` evaluates to the transaction start time in Postgres and does NOT advance across statements.
   - Do NOT attempt to sleep or wait for expiration in SQL.
   - Explicitly update timestamps backwards (e.g. `update rooms set expires_at = now() - interval '10 minutes'`) to test expiration and retirement logic.

3. **RLS & Role Testing**:
   Use `tests.authenticate_as('user-uuid')` or set `request.jwt.claims` to test Row-Level Security policies and host vs member permissions.
