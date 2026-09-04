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
  MX: { currency: "MXN", symbol: "M$" },
  PH: { currency: "PHP", symbol: "₱" },
  NG: { currency: "NGN", symbol: "₦" },
  PK: { currency: "PKR", symbol: "₨" },
};

const ZERO_DECIMAL_CURRENCIES = new Set(["INR", "JPY", "KRW", "VND", "CLP", "HUF", "TWD"]);

const DISAMBIGUATED_CURRENCY_SYMBOLS: Record<string, string> = {
  MXN: "M$",
  CAD: "CA$",
  AUD: "A$",
  NZD: "NZ$",
  SGD: "S$",
  HKD: "HK$",
  BRL: "R$",
  ARS: "AR$",
  CLP: "CL$",
  COP: "COL$",
  TWD: "NT$",
};

function calculateSavingsPercentage(monthlyAmount: number, annualAmount: number): string {
  if (!monthlyAmount || !annualAmount || monthlyAmount <= 0) return "37%";
  const fullAnnualCost = monthlyAmount * 12;
  const savings = ((fullAnnualCost - annualAmount) / fullAnnualCost) * 100;
  return `${Math.max(1, Math.round(savings))}%`;
}

function formatCurrency(amount: number, currencyCode: string, countryCode?: string): string {
  const isUsdOutsideUs = currencyCode === "USD" && Boolean(countryCode && countryCode !== "US");
  const disambiguated = isUsdOutsideUs ? "US$" : DISAMBIGUATED_CURRENCY_SYMBOLS[currencyCode];
  const isZeroDecimal = ZERO_DECIMAL_CURRENCIES.has(currencyCode) || (amount % 1 === 0 && currencyCode === "INR");
  const fractionDigits = isZeroDecimal ? 0 : 2;

  if (disambiguated) {
    const formattedNum = new Intl.NumberFormat("en-US", {
      minimumFractionDigits: fractionDigits,
      maximumFractionDigits: fractionDigits,
    }).format(amount);
    return `${disambiguated}${formattedNum}`;
  }

  try {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: currencyCode,
      minimumFractionDigits: fractionDigits,
      maximumFractionDigits: fractionDigits,
    }).format(amount);
  } catch {
    const symbol = resolveCurrencySymbol(currencyCode, countryCode);
    return `${symbol}${amount.toFixed(fractionDigits)}`;
  }
}

function resolveCurrencySymbol(currencyCode: string, countryCode?: string): string {
  if (currencyCode === "USD" && countryCode && countryCode !== "US") {
    return "US$";
  }
  return (
    DISAMBIGUATED_CURRENCY_SYMBOLS[currencyCode] ||
    (countryCode && COUNTRY_CURRENCY_MAP[countryCode]?.symbol) ||
    "$"
  );
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
  assert.equal(COUNTRY_CURRENCY_MAP.MX.currency, "MXN");
  assert.equal(COUNTRY_CURRENCY_MAP.MX.symbol, "M$");
  assert.equal(COUNTRY_CURRENCY_MAP.PH.currency, "PHP");
  assert.equal(COUNTRY_CURRENCY_MAP.PH.symbol, "₱");
  assert.equal(COUNTRY_CURRENCY_MAP.NG.currency, "NGN");
  assert.equal(COUNTRY_CURRENCY_MAP.NG.symbol, "₦");
  assert.equal(COUNTRY_CURRENCY_MAP.PK.currency, "PKR");
  assert.equal(COUNTRY_CURRENCY_MAP.PK.symbol, "₨");

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

  // ₹199 * 12 = ₹2388 -> ₹999 is ~58.16% savings
  const savingsInr = calculateSavingsPercentage(199, 999);
  assert.equal(savingsInr, "58%");
});

test("Currency conversion and decimal rounding handles whole and fractional amounts with disambiguation", () => {
  const inrAmount = 199;
  assert.equal(inrAmount % 1 === 0, true);
  assert.equal(formatCurrency(199, "INR"), "₹199");

  const usdAmount = 3.99;
  assert.equal(usdAmount % 1 !== 0, true);
  assert.equal(formatCurrency(3.99, "USD", "US"), "$3.99");
  assert.equal(formatCurrency(2.29, "USD", "PH"), "US$2.29");
  assert.equal(formatCurrency(2.29, "USD", "NG"), "US$2.29");

  // Ambiguous currency symbols must be cleanly disambiguated
  assert.equal(formatCurrency(59, "MXN"), "M$59.00");
  assert.equal(formatCurrency(349, "MXN"), "M$349.00");
  assert.equal(formatCurrency(4.99, "CAD"), "CA$4.99");
  assert.equal(formatCurrency(5.99, "AUD"), "A$5.99");
  assert.equal(formatCurrency(14.9, "BRL"), "R$14.90");
  assert.equal(formatCurrency(120, "TWD"), "NT$120");

  assert.equal(resolveCurrencySymbol("USD", "US"), "$");
  assert.equal(resolveCurrencySymbol("USD", "PH"), "US$");
  assert.equal(resolveCurrencySymbol("MXN", "MX"), "M$");
  assert.equal(resolveCurrencySymbol("CAD", "CA"), "CA$");
  assert.equal(resolveCurrencySymbol("PHP", "PH"), "₱");
  assert.equal(resolveCurrencySymbol("NGN", "NG"), "₦");
  assert.equal(resolveCurrencySymbol("PKR", "PK"), "₨");
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


