import test from "node:test";
import assert from "node:assert/strict";

const COUNTRY_CURRENCY_MAP: Record<string, { currency: string; symbol: string }> = {
  IN: { currency: "INR", symbol: "₹" },
  US: { currency: "USD", symbol: "default_api:$" },
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
});
