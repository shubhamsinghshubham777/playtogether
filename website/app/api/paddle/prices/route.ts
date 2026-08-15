import { NextResponse } from "next/server";

export async function GET() {
  try {
    const monthlyPriceId =
      process.env.NEXT_PUBLIC_PADDLE_MONTHLY_PRICE_ID ||
      process.env.PADDLE_MONTHLY_PRICE_ID;
    const annualPriceId =
      process.env.NEXT_PUBLIC_PADDLE_ANNUAL_PRICE_ID ||
      process.env.PADDLE_ANNUAL_PRICE_ID;
    const apiKey = process.env.PADDLE_API_KEY;

    if (
      apiKey &&
      monthlyPriceId &&
      annualPriceId &&
      !apiKey.includes("xxx")
    ) {
      // In production with live Paddle API key, fetch real localized prices
      const env = process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT === "production"
        ? "https://api.paddle.com"
        : "https://sandbox-api.paddle.com";

      const res = await fetch(`${env}/prices?include=product`, {
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
        next: { revalidate: 3600 },
      });

      if (res.ok) {
        const data = await res.json();
        return NextResponse.json(data);
      }
    }

    // Default static pricing data fallback
    return NextResponse.json({
      monthly: {
        priceId: monthlyPriceId || "pri_monthly_default",
        formatted: "$3.99",
        amount: "3.99",
        currency: "USD",
      },
      annual: {
        priceId: annualPriceId || "pri_annual_default",
        formatted: "$29.99",
        amount: "29.99",
        currency: "USD",
        monthlyEquivalent: "$2.49",
      },
    });
  } catch (error) {
    console.error("Paddle prices route error:", error);
    return NextResponse.json(
      { error: "Failed to fetch prices" },
      { status: 500 }
    );
  }
}
