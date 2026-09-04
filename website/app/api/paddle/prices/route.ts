import { NextRequest, NextResponse } from "next/server";
import {
  COUNTRY_CURRENCY_MAP,
  PADDLE_SUPPORTED_CURRENCIES,
  formatCurrency,
  resolveCurrencySymbol,
  calculateSavingsPercentage,
} from "@/lib/pricing";

const FALLBACK_PRICES: Record<string, { m: number; a: number }> = {
  INR: { m: 199, a: 999 },
  USD: { m: 3.99, a: 29.99 },
  GBP: { m: 3.49, a: 24.99 },
  EUR: { m: 3.99, a: 29.99 },
  CAD: { m: 4.99, a: 37.99 },
  AUD: { m: 5.99, a: 44.99 },
  JPY: { m: 550, a: 4200 },
  BRL: { m: 14.90, a: 69.90 },
  MXN: { m: 59, a: 349 },
  PLN: { m: 11.99, a: 84.99 },
  TRY: { m: 89, a: 429 },
};

const TIER3_PPP_COUNTRIES = new Set([
  "PK", "BD", "LK", "NP", "BT", "MV", "NG", "KE", "EG", "GH", "MA", "DZ", "TN", "UG",
  "ET", "TZ", "SN", "RW", "CM", "CI", "PH", "VN", "ID", "KH", "LA", "MM", "CO", "PE",
  "AR", "BO", "EC", "PY", "VE", "GT", "HN", "SV", "NI", "DO", "UA", "GE", "AM", "AZ",
  "MD", "UZ", "KZ", "KG", "TJ",
]);

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const country = (searchParams.get("country") || "US").toUpperCase();
    const countryConfig = COUNTRY_CURRENCY_MAP[country] || COUNTRY_CURRENCY_MAP["US"];
    const targetCurrency = searchParams.get("currency") || countryConfig.currency;
    const isCurrencySupported = PADDLE_SUPPORTED_CURRENCIES.has(targetCurrency);

    const monthlyPriceId =
      process.env.NEXT_PUBLIC_PADDLE_MONTHLY_PRICE_ID ||
      process.env.PADDLE_MONTHLY_PRICE_ID ||
      "pri_01m02w4z770krsa3sw2ydsskgs";
    const annualPriceId =
      process.env.NEXT_PUBLIC_PADDLE_ANNUAL_PRICE_ID ||
      process.env.PADDLE_ANNUAL_PRICE_ID ||
      "pri_01m02w6w151nd2em52yrpar44y";
    const apiKey = process.env.PADDLE_API_KEY;

    if (apiKey && !apiKey.includes("xxx")) {
      const envUrl =
        process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT === "production"
          ? "https://api.paddle.com"
          : "https://sandbox-api.paddle.com";

      try {
        const previewPayload: Record<string, unknown> = {
          items: [
            { price_id: monthlyPriceId, quantity: 1 },
            { price_id: annualPriceId, quantity: 1 },
          ],
          address: { country_code: country },
        };
        if (isCurrencySupported) {
          previewPayload.currency_code = targetCurrency;
        }

        const previewRes = await fetch(`${envUrl}/pricing-preview`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(previewPayload),
          next: { revalidate: 60 },
        });

        if (previewRes.ok) {
          const previewData = await previewRes.json();
          const lineItems =
            previewData.data?.details?.line_items ||
            previewData.data?.details?.lineItems ||
            [];
          const monthlyItem = lineItems.find(
            (item: { price?: { id?: string } }) => item.price?.id === monthlyPriceId
          ) || lineItems[0];
          const annualItem = lineItems.find(
            (item: { price?: { id?: string } }) => item.price?.id === annualPriceId
          ) || lineItems[1];

          if (monthlyItem && annualItem) {
            const currencyCode = previewData.data?.currency_code || (isCurrencySupported ? targetCurrency : "USD");
            const currencySymbol = resolveCurrencySymbol(currencyCode, country);

            // Parse total amounts
            const monthlyTotal = parseFloat(monthlyItem.totals?.total || "399") / 100;
            const annualTotal = parseFloat(annualItem.totals?.total || "2999") / 100;
            const monthlyEq = Math.round((annualTotal / 12) * 100) / 100;

            const savingsPct = calculateSavingsPercentage(monthlyTotal, annualTotal);

            return NextResponse.json({
              currencyCode,
              currencySymbol,
              countryCode: country,
              monthlyFormatted: formatCurrency(monthlyTotal, currencyCode, country),
              monthlyAmount: monthlyTotal,
              annualFormatted: formatCurrency(annualTotal, currencyCode, country),
              annualAmount: annualTotal,
              monthlyEquivalentFormatted: `${formatCurrency(monthlyEq, currencyCode, country)} / mo`,
              monthlyEquivalentAmount: monthlyEq,
              savingsPct,
              source: "paddle_api",
            });
          }
        }
      } catch (paddleErr) {
        console.error("Paddle pricing preview API error:", paddleErr);
      }
    }

    // Default localized fallback when Paddle API key is offline / not reachable
    const isTier3 = TIER3_PPP_COUNTRIES.has(country);
    const currency = isTier3 ? "USD" : (targetCurrency in FALLBACK_PRICES ? targetCurrency : "USD");
    const prices = isTier3 ? { m: 2.29, a: 11.99 } : (FALLBACK_PRICES[currency] || FALLBACK_PRICES["USD"]);
    const monthlyEq = Math.round((prices.a / 12) * 100) / 100;
    const currencySymbol = resolveCurrencySymbol(currency, country);

    return NextResponse.json({
      currencyCode: currency,
      currencySymbol,
      countryCode: country,
      monthlyFormatted: formatCurrency(prices.m, currency, country),
      monthlyAmount: prices.m,
      annualFormatted: formatCurrency(prices.a, currency, country),
      annualAmount: prices.a,
      monthlyEquivalentFormatted: `${formatCurrency(monthlyEq, currency, country)} / mo`,
      monthlyEquivalentAmount: monthlyEq,
      savingsPct: calculateSavingsPercentage(prices.m, prices.a),
      source: "fallback",
    });
  } catch (error) {
    console.error("Paddle prices route error:", error);
    return NextResponse.json(
      { error: "Failed to fetch prices" },
      { status: 500 }
    );
  }
}
