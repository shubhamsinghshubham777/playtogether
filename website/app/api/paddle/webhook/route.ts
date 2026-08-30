import { NextResponse } from "next/server";
import crypto from "crypto";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(request: Request) {
  try {
    const rawBody = await request.text();
    const signatureHeader = request.headers.get("paddle-signature");
    const webhookSecret = process.env.PADDLE_WEBHOOK_SECRET_KEY;

    if (webhookSecret && signatureHeader) {
      const parts = signatureHeader.split(";").reduce((acc, part) => {
        const [k, v] = part.split("=");
        if (k && v) acc[k.trim()] = v.trim();
        return acc;
      }, {} as Record<string, string>);

      const ts = parts["ts"];
      const h1 = parts["h1"];

      if (ts && h1) {
        const expectedSignature = crypto
          .createHmac("sha256", webhookSecret)
          .update(`${ts}:${rawBody}`)
          .digest("hex");

        if (expectedSignature !== h1) {
          console.error("Invalid Paddle webhook signature");
          return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
        }
      }
    }

    const event = JSON.parse(rawBody);
    const eventType = event.event_type;
    const data = event.data;
    const userId = data?.custom_data?.user_id;

    if (!userId) {
      console.warn("Paddle webhook received without custom_data.user_id:", eventType);
      return NextResponse.json({ received: true });
    }

    const supabase = createAdminClient();
    const isDeactivation =
      eventType === "subscription.canceled" ||
      eventType === "subscription.past_due" ||
      eventType === "subscription.paused" ||
      data?.status === "canceled" ||
      data?.status === "paused" ||
      data?.status === "past_due";

    if (isDeactivation) {
      const { error } = await supabase.from("subscriptions").delete().eq("user_id", userId);
      if (error) {
        console.error("Failed to delete subscription:", error);
        return NextResponse.json({ error: "Database delete error" }, { status: 500 });
      }
    } else if (
      eventType === "subscription.activated" ||
      eventType === "subscription.created" ||
      eventType === "subscription.updated" ||
      eventType === "transaction.completed"
    ) {
      const currentPeriodEnd =
        data?.current_billing_period?.ends_at ||
        data?.billing_period?.ends_at ||
        new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

      const { data: existing } = await supabase
        .from("subscriptions")
        .select("tier, current_period_end")
        .eq("user_id", userId)
        .maybeSingle();

      if (
        existing?.tier === "premium" &&
        existing?.current_period_end === currentPeriodEnd
      ) {
        return NextResponse.json({ success: true, deduplicated: true });
      }

      const { error } = await supabase.from("subscriptions").upsert(
        {
          user_id: userId,
          tier: "premium",
          source: "paddle",
          current_period_end: currentPeriodEnd,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" }
      );

      if (error) {
        console.error("Failed to upsert subscription:", error);
        return NextResponse.json({ error: "Database error" }, { status: 500 });
      }
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Paddle webhook handling error:", error);
    return NextResponse.json({ error: "Webhook processing error" }, { status: 500 });
  }
}
