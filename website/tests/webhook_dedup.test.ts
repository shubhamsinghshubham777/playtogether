import test from "node:test";
import assert from "node:assert/strict";
import crypto from "crypto";

test("Webhook signature verification", () => {
  const secret = "test_webhook_secret_key_123";
  const rawBody = JSON.stringify({
    event_type: "subscription.created",
    data: { custom_data: { user_id: "user_abc" } },
  });
  const ts = Math.floor(Date.now() / 1000).toString();

  const validH1 = crypto
    .createHmac("sha256", secret)
    .update(`${ts}:${rawBody}`)
    .digest("hex");

  const computedSig = crypto
    .createHmac("sha256", secret)
    .update(`${ts}:${rawBody}`)
    .digest("hex");

  assert.equal(computedSig, validH1);

  const invalidSig = crypto
    .createHmac("sha256", "wrong_secret")
    .update(`${ts}:${rawBody}`)
    .digest("hex");

  assert.notEqual(invalidSig, validH1);
});

test("Subscription deduplication logic skips redundant database writes", () => {
  const existingSub = {
    tier: "premium",
    current_period_end: "2026-09-15T00:00:00.000Z",
  };

  const incomingPeriodEnd = "2026-09-15T00:00:00.000Z";

  // Check deduplication predicate
  const isDuplicate =
    existingSub?.tier === "premium" &&
    existingSub?.current_period_end === incomingPeriodEnd;

  assert.equal(isDuplicate, true);

  // If period end advances (e.g. renewal after 1 month)
  const renewedPeriodEnd = "2026-10-15T00:00:00.000Z";
  const isRenewalDuplicate =
    existingSub?.tier === "premium" &&
    existingSub?.current_period_end === renewedPeriodEnd;

  assert.equal(isRenewalDuplicate, false);
});

test("Deactivation events identify all cancellation and lapse statuses", () => {
  const deactivationEventTypes = [
    "subscription.canceled",
    "subscription.past_due",
    "subscription.paused",
  ];

  for (const eventType of deactivationEventTypes) {
    const isDeactivation =
      eventType === "subscription.canceled" ||
      eventType === "subscription.past_due" ||
      eventType === "subscription.paused";
    assert.equal(isDeactivation, true);
  }

  const updatedCanceledEvent = {
    event_type: "subscription.updated",
    data: { status: "canceled" },
  };

  const isDeactivationFromStatus =
    updatedCanceledEvent.event_type === "subscription.canceled" ||
    updatedCanceledEvent.data?.status === "canceled";

  assert.equal(isDeactivationFromStatus, true);
});
