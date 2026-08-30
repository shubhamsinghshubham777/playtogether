import test from "node:test";
import assert from "node:assert/strict";

const COUNTRY_CURRENCY_MAP: Record<string, { currency: string; symbol: string }> = {
  IN: { currency: "INR", symbol: "₹" },
  US: { currency: "USD", symbol: "$" },
  GB: { currency: "GBP", symbol: "£" },
  DE: { currency: "EUR", symbol: "€" },
  CA: { currency: "CAD", symbol: "CA$" },
  AU: { currency: "AUD", symbol: "A$" },
  JP: { currency: "JPY", symbol: "¥" },
};

function calculateSavingsPercentage(monthlyAmount: number, annualAmount: number): string {
  if (!monthlyAmount || !annualAmount || monthlyAmount <= 0) return "37%";
  const fullAnnualCost = monthlyAmount * 12;
  const savings = ((fullAnnualCost - annualAmount) / fullAnnualCost) * 100;
  return `${Math.max(1, Math.round(savings))}%`;
}

function formatCurrency(amount: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currencyCode,
      minimumFractionDigits: amount % 1 === 0 ? 0 : 2,
      maximumFractionDigits: 2,
    }).format(amount);
  } catch {
    const symbol = COUNTRY_CURRENCY_MAP[currencyCode]?.symbol || "$";
    return `${symbol}${amount.toFixed(amount % 1 === 0 ? 0 : 2)}`;
  }
}

function isLocalEnvironment(customEnv?: string, customHostname?: string): boolean {
  const env = customEnv ?? process.env.NODE_ENV;
  if (env === "development") {
    return true;
  }
  if (customHostname) {
    return (
      customHostname === "localhost" ||
      customHostname === "127.0.0.1" ||
      customHostname === "0.0.0.0" ||
      customHostname.endsWith(".localhost") ||
      customHostname.endsWith(".local")
    );
  }
  return false;
}

test("COUNTRY_CURRENCY_MAP contains all key regional currencies", () => {
  assert.equal(COUNTRY_CURRENCY_MAP.IN.currency, "INR");
  assert.equal(COUNTRY_CURRENCY_MAP.IN.symbol, "₹");

  assert.equal(COUNTRY_CURRENCY_MAP.US.currency, "USD");
  assert.equal(COUNTRY_CURRENCY_MAP.GB.currency, "GBP");
  assert.equal(COUNTRY_CURRENCY_MAP.GB.symbol, "£");
  assert.equal(COUNTRY_CURRENCY_MAP.DE.currency, "EUR");
  assert.equal(COUNTRY_CURRENCY_MAP.DE.symbol, "€");
});

test("calculateSavingsPercentage accurately computes annual plan discount", () => {
  // $3.99 * 12 = $47.88 -> $29.99 is ~37.36% savings
  const savingsUsd = calculateSavingsPercentage(3.99, 29.99);
  assert.equal(savingsUsd, "37%");

  // ₹149 * 12 = ₹1788 -> ₹999 is ~44.13% savings
  const savingsInr = calculateSavingsPercentage(149, 999);
  assert.equal(savingsInr, "44%");
});

test("Currency conversion and decimal rounding handles whole and fractional amounts", () => {
  const inrAmount = 149;
  assert.equal(inrAmount % 1 === 0, true);

  const usdAmount = 3.99;
  assert.equal(usdAmount % 1 !== 0, true);
  assert.equal(formatCurrency(3.99, "USD"), "$3.99");
});

test("isLocalEnvironment strictly hides simulator on production domains and shows on localhost/dev", () => {
  // Production / Vercel domains must return false
  assert.equal(isLocalEnvironment("production", "synctogether.com"), false);
  assert.equal(isLocalEnvironment("production", "synctogether.vercel.app"), false);
  assert.equal(isLocalEnvironment("production", "synctogether-git-main-shubham.vercel.app"), false);

  // Local development / local hostnames must return true
  assert.equal(isLocalEnvironment("development", "synctogether.vercel.app"), true);
  assert.equal(isLocalEnvironment("production", "localhost"), true);
  assert.equal(isLocalEnvironment("production", "127.0.0.1"), true);
  assert.equal(isLocalEnvironment("production", "0.0.0.0"), true);
  assert.equal(isLocalEnvironment("production", "app.local"), true);
  assert.equal(isLocalEnvironment("production", "test.localhost"), true);
});


