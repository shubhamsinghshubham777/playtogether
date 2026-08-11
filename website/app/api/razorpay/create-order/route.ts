import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json(
        { error: "Authentication required" },
        { status: 401 }
      );
    }

    const body = await request.json();
    const { plan } = body; // '1mo' | '12mo'

    const amount =
      plan === "12mo"
        ? parseInt(process.env.RAZORPAY_PLAN_12MO_AMOUNT || "99900", 10)
        : parseInt(process.env.RAZORPAY_PLAN_1MO_AMOUNT || "14900", 10);

    const keyId = process.env.NEXT_PUBLIC_RAZORPAY_KEY_ID;
    const keySecret = process.env.RAZORPAY_KEY_SECRET;

    // Check if real Razorpay credentials exist
    if (
      keyId &&
      keySecret &&
      !keyId.includes("dummy") &&
      !keySecret.includes("dummy")
    ) {
      const authHeader = `Basic ${Buffer.from(
        `${keyId}:${keySecret}`
      ).toString("base64")}`;

      const response = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: authHeader,
        },
        body: JSON.stringify({
          amount,
          currency: "INR",
          receipt: `rcpt_${user.id.slice(0, 8)}_${Date.now()}`,
          notes: {
            user_id: user.id,
            plan: plan || "1mo",
          },
        }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        console.error("Razorpay order creation error:", errorData);
        return NextResponse.json(
          { error: errorData.error?.description || "Order creation failed" },
          { status: 500 }
        );
      }

      const orderData = await response.json();
      return NextResponse.json({
        orderId: orderData.id,
        amount: orderData.amount,
        currency: orderData.currency,
        keyId,
      });
    }

    // Development / Sandbox simulation fallback
    return NextResponse.json({
      orderId: `order_sandbox_${Date.now()}`,
      amount,
      currency: "INR",
      keyId: keyId || "rzp_test_sandbox",
      isDevFallback: true,
    });
  } catch (error) {
    console.error("Razorpay API route error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
