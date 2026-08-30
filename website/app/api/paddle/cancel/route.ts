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
    const apiKey = process.env.PADDLE_API_KEY;
    const isSandbox = process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT !== "production";

    if (apiKey && !apiKey.includes("xxx")) {
      const paddleApiHost = isSandbox
        ? "https://sandbox-api.paddle.com"
        : "https://api.paddle.com";

      try {
        const res = await fetch(`${paddleApiHost}/subscriptions?per_page=20`, {
          headers: {
            Authorization: `Bearer ${apiKey}`,
          },
        });

        if (res.ok) {
          const body = await res.json();
          const userSub = body?.data?.find(
            (s: { custom_data?: { user_id?: string }; status?: string }) =>
              s.custom_data?.user_id === user.id && s.status === "active"
          );

          if (userSub?.id) {
            await fetch(`${paddleApiHost}/subscriptions/${userSub.id}/cancel`, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${apiKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({ effective_from: "immediately" }),
            });
          }
        }
      } catch (err) {
        console.warn("Paddle API cancellation warning (proceeding with DB deletion):", err);
      }
    }

    const { error: deleteError } = await adminSupabase
      .from("subscriptions")
      .delete()
      .eq("user_id", user.id);

    if (deleteError) {
      console.error("Failed to delete subscription in Supabase:", deleteError);
      return NextResponse.json(
        { error: "Failed to update subscription" },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true, tier: "free" });
  } catch (error) {
    console.error("Cancel subscription route error:", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
