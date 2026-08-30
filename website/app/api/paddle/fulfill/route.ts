import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST() {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const adminSupabase = createAdminClient();

    // Check if subscription row already exists
    const { data: existingSub } = await adminSupabase
      .from("subscriptions")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    if (existingSub && existingSub.tier === "premium") {
      return NextResponse.json({
        success: true,
        subscription: existingSub,
        tier: "premium",
      });
    }

    // If apiKey is configured and in sandbox/prod, attempt to query Paddle for customer subscription
    const apiKey = process.env.PADDLE_API_KEY;
    const isSandbox = process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT !== "production";
    let periodEnd = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

    if (apiKey && !apiKey.includes("xxx")) {
      const paddleApiHost = isSandbox
        ? "https://sandbox-api.paddle.com"
        : "https://api.paddle.com";

      try {
        // Query recent transactions or subscriptions
        const res = await fetch(`${paddleApiHost}/subscriptions?customer_id=&per_page=10`, {
          headers: {
            Authorization: `Bearer ${apiKey}`,
          },
        });

        if (res.ok) {
          const body = await res.json();
          const userSub = body?.data?.find(
            (s: { custom_data?: { user_id?: string } }) =>
              s.custom_data?.user_id === user.id
          );
          if (userSub?.current_billing_period?.ends_at) {
            periodEnd = userSub.current_billing_period.ends_at;
          }
        }
      } catch (err) {
        console.warn("Paddle API verification error (falling back to default period):", err);
      }
    }

    // Upsert subscription
    const { data: newSub, error: upsertError } = await adminSupabase
      .from("subscriptions")
      .upsert(
        {
          user_id: user.id,
          tier: "premium",
          source: "paddle",
          current_period_end: periodEnd,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" }
      )
      .select()
      .single();

    if (upsertError) {
      console.error("Failed to fulfill subscription:", upsertError);
      return NextResponse.json({ error: "Failed to update subscription" }, { status: 500 });
    }

    return NextResponse.json({
      success: true,
      subscription: newSub,
      tier: "premium",
    });
  } catch (error) {
    console.error("Fulfill subscription route error:", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
