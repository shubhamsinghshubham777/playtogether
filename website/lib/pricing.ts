export interface CountryConfig {
  country: string;
  currency: string;
  name: string;
  flag: string;
  symbol: string;
}

export const COUNTRY_CURRENCY_MAP: Record<string, CountryConfig> = {
  IN: { country: "IN", currency: "INR", name: "India", flag: "🇮🇳", symbol: "₹" },
  US: { country: "US", currency: "USD", name: "United States", flag: "🇺🇸", symbol: "$" },
  GB: { country: "GB", currency: "GBP", name: "United Kingdom", flag: "🇬🇧", symbol: "£" },
  DE: { country: "DE", currency: "EUR", name: "Germany (EU)", flag: "🇩🇪", symbol: "€" },
  FR: { country: "FR", currency: "EUR", name: "France (EU)", flag: "🇫🇷", symbol: "€" },
  CA: { country: "CA", currency: "CAD", name: "Canada", flag: "🇨🇦", symbol: "CA$" },
  AU: { country: "AU", currency: "AUD", name: "Australia", flag: "🇦🇺", symbol: "A$" },
  JP: { country: "JP", currency: "JPY", name: "Japan", flag: "🇯🇵", symbol: "¥" },
  BR: { country: "BR", currency: "BRL", name: "Brazil", flag: "🇧🇷", symbol: "R$" },
  MX: { country: "MX", currency: "MXN", name: "Mexico", flag: "🇲🇽", symbol: "Mex$" },
  PL: { country: "PL", currency: "PLN", name: "Poland", flag: "🇵🇱", symbol: "zł" },
  TR: { country: "TR", currency: "TRY", name: "Turkey", flag: "🇹🇷", symbol: "₺" },
  NG: { country: "NG", currency: "USD", name: "Nigeria", flag: "🇳🇬", symbol: "$" },
  PK: { country: "PK", currency: "USD", name: "Pakistan", flag: "🇵🇰", symbol: "$" },
  PH: { country: "PH", currency: "USD", name: "Philippines", flag: "🇵🇭", symbol: "$" },
};

export interface LocalizedPriceData {
  monthlyFormatted: string;
  monthlyAmount: number;
  annualFormatted: string;
  annualAmount: number;
  monthlyEquivalentFormatted: string;
  monthlyEquivalentAmount: number;
  currencyCode: string;
  currencySymbol: string;
  countryCode: string;
  savingsPct: string;
  rawResponse?: unknown;
}

/**
 * Formats a currency amount with symbol and appropriate decimals
 */
export function formatCurrency(amount: number, currencyCode: string): string {
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

/**
 * Checks whether the current environment is local development or local testing
 */
export function isLocalEnvironment(): boolean {
  if (process.env.NODE_ENV === "development") {
    return true;
  }
  if (typeof window !== "undefined") {
    const hostname = window.location.hostname;
    return (
      hostname === "localhost" ||
      hostname === "127.0.0.1" ||
      hostname === "0.0.0.0" ||
      hostname.endsWith(".localhost") ||
      hostname.endsWith(".local")
    );
  }
  return false;
}

/**
 * Detects user country from timezone or browser locale
 */
export function detectUserCountry(): string {
  if (typeof window === "undefined") return "US";

  // Mock overrides are strictly allowed only in local development / testing
  if (isLocalEnvironment()) {
    // 1. Check URL search param
    const urlParams = new URLSearchParams(window.location.search);
    const paramCountry = urlParams.get("mock_country") || urlParams.get("country");
    if (paramCountry && COUNTRY_CURRENCY_MAP[paramCountry.toUpperCase()]) {
      return paramCountry.toUpperCase();
    }

    // 2. Check localStorage
    const stored = localStorage.getItem("synctogether_mock_country");
    if (stored && COUNTRY_CURRENCY_MAP[stored.toUpperCase()]) {
      return stored.toUpperCase();
    }
  }

  // 3. Infer from Timezone
  try {
    const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (timeZone.startsWith("Asia/Calcutta") || timeZone.startsWith("Asia/Kolkata")) {
      return "IN";
    }
    if (timeZone.startsWith("Europe/London")) {
      return "GB";
    }
    if (
      timeZone.startsWith("Europe/Berlin") ||
      timeZone.startsWith("Europe/Paris") ||
      timeZone.startsWith("Europe/Rome") ||
      timeZone.startsWith("Europe/Madrid") ||
      timeZone.startsWith("Europe/Amsterdam")
    ) {
      return "DE";
    }
    if (timeZone.startsWith("America/Toronto") || timeZone.startsWith("America/Vancouver")) {
      return "CA";
    }
    if (timeZone.startsWith("Australia/")) {
      return "AU";
    }
    if (timeZone.startsWith("Asia/Tokyo")) {
      return "JP";
    }
    if (timeZone.startsWith("America/")) {
      return "US";
    }
  } catch {
    // ignore Intl errors
  }

  // 4. Infer from navigator language
  if (typeof navigator !== "undefined" && navigator.languages) {
    for (const lang of navigator.languages) {
      if (lang.includes("-IN") || lang === "hi" || lang === "en-IN") return "IN";
      if (lang.includes("-GB")) return "GB";
      if (lang.includes("-DE")) return "DE";
      if (lang.includes("-FR")) return "FR";
      if (lang.includes("-CA")) return "CA";
      if (lang.includes("-AU")) return "AU";
      if (lang.includes("-JP") || lang === "ja") return "JP";
      if (lang.includes("-US")) return "US";
    }
  }

  return "US";
}

/**
 * Calculates savings percentage between annual and monthly pricing
 */
export function calculateSavingsPercentage(monthlyAmount: number, annualAmount: number): string {
  if (!monthlyAmount || !annualAmount || monthlyAmount <= 0) return "37%";
  const fullAnnualCost = monthlyAmount * 12;
  const savings = ((fullAnnualCost - annualAmount) / fullAnnualCost) * 100;
  return `${Math.max(1, Math.round(savings))}%`;
}
