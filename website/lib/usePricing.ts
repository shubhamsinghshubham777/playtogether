"use client";

import { useEffect, useState, useCallback, useSyncExternalStore } from "react";
import { getPaddleInstance } from "@/components/PaddleCheckout";
import {
  COUNTRY_CURRENCY_MAP,
  PADDLE_SUPPORTED_CURRENCIES,
  detectUserCountry,
  formatCurrency,
  resolveCurrencySymbol,
  calculateSavingsPercentage,
  isLocalEnvironment,
  type LocalizedPriceData,
} from "./pricing";

const PADDLE_MONTHLY_PRICE_ID =
  process.env.NEXT_PUBLIC_PADDLE_MONTHLY_PRICE_ID || "pri_01m02w4z770krsa3sw2ydsskgs";
const PADDLE_ANNUAL_PRICE_ID =
  process.env.NEXT_PUBLIC_PADDLE_ANNUAL_PRICE_ID || "pri_01m02w6w151nd2em52yrpar44y";

// In-memory client-side price cache to eliminate duplicate network calls
const clientPriceCache: Record<string, LocalizedPriceData> = {};

function subscribeMockCountry(callback: () => void) {
  if (typeof window === "undefined" || !isLocalEnvironment()) return () => {};
  window.addEventListener("pt_mock_country_changed", callback);
  window.addEventListener("storage", callback);
  return () => {
    window.removeEventListener("pt_mock_country_changed", callback);
    window.removeEventListener("storage", callback);
  };
}

function getMockCountrySnapshot(): string | null {
  if (typeof window === "undefined" || !isLocalEnvironment()) return null;
  const urlParams = new URLSearchParams(window.location.search);
  const paramMock = urlParams.get("mock_country") || urlParams.get("country");
  const storedMock = localStorage.getItem("synctogether_mock_country");
  const activeMock = paramMock || storedMock || null;
  return activeMock ? activeMock.toUpperCase() : null;
}

function getMockCountryServerSnapshot(): string | null {
  return null;
}

export function usePricing() {
  const [data, setData] = useState<LocalizedPriceData>({
    monthlyFormatted: "$3.99",
    monthlyAmount: 3.99,
    annualFormatted: "$29.99",
    annualAmount: 29.99,
    monthlyEquivalentFormatted: "$2.49 / mo",
    monthlyEquivalentAmount: 2.49,
    currencyCode: "USD",
    currencySymbol: "$",
    countryCode: "US",
    savingsPct: "37%",
  });
  const [isLoading, setIsLoading] = useState<boolean>(true);

  // Synchronize mock country cleanly across server/client with zero hydration mismatch
  const mockCountry = useSyncExternalStore(
    subscribeMockCountry,
    getMockCountrySnapshot,
    getMockCountryServerSnapshot
  );

  const setMockCountry = useCallback((country: string | null) => {
    if (!isLocalEnvironment()) return;
    if (country) {
      const upper = country.toUpperCase();
      localStorage.setItem("synctogether_mock_country", upper);
    } else {
      localStorage.removeItem("synctogether_mock_country");
    }
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("pt_mock_country_changed", { detail: country }));
    }
  }, []);

  // Expose global helper for automated testing and developer console (local development only)
  useEffect(() => {
    if (typeof window !== "undefined" && isLocalEnvironment()) {
      (window as unknown as { __setMockCountry?: (c: string | null) => void }).__setMockCountry = setMockCountry;
    }
    return () => {
      if (typeof window !== "undefined") {
        delete (window as unknown as { __setMockCountry?: (c: string | null) => void }).__setMockCountry;
      }
    };
  }, [setMockCountry]);

  const fetchPricing = useCallback(async () => {
    const country = mockCountry || detectUserCountry();
    const countryConfig = COUNTRY_CURRENCY_MAP[country] || COUNTRY_CURRENCY_MAP["US"];
    const targetCurrency = countryConfig.currency;

    // Check memory cache first
    if (clientPriceCache[country]) {
      setData(clientPriceCache[country]);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);

    try {
      // 1. Try fetching via Paddle.js client SDK PricePreview
      const paddle = await getPaddleInstance();
      if (paddle && typeof paddle.PricePreview === "function") {
        try {
          const isSupported = PADDLE_SUPPORTED_CURRENCIES.has(targetCurrency);
          const previewPayload: {
            items: { priceId: string; quantity: number }[];
            address: { countryCode: string };
            currencyCode?: "USD" | "EUR" | "GBP" | "INR" | "CAD" | "AUD" | "JPY";
          } = {
            items: [
              { priceId: PADDLE_MONTHLY_PRICE_ID, quantity: 1 },
              { priceId: PADDLE_ANNUAL_PRICE_ID, quantity: 1 },
            ],
            address: { countryCode: country },
          };
          if (isSupported) {
            previewPayload.currencyCode = targetCurrency as "USD" | "EUR" | "GBP" | "INR" | "CAD" | "AUD" | "JPY";
          }

          const preview = await paddle.PricePreview(previewPayload);

          if (preview?.data?.details?.lineItems?.length) {
            const lineItems = preview.data.details.lineItems;
            const monthlyItem =
              lineItems.find((item) => item.price?.id === PADDLE_MONTHLY_PRICE_ID) ||
              lineItems[0];
            const annualItem =
              lineItems.find((item) => item.price?.id === PADDLE_ANNUAL_PRICE_ID) ||
              lineItems[1];

            const currencyCode = preview.data.currencyCode || (isSupported ? targetCurrency : "USD");
            const currencySymbol = resolveCurrencySymbol(currencyCode, country);

            const monthlyTotal =
              parseFloat(monthlyItem.totals?.total || monthlyItem.unitTotals?.total || "399") / 100;
            const annualTotal =
              parseFloat(annualItem.totals?.total || annualItem.unitTotals?.total || "2999") / 100;
            const monthlyEq = Math.round((annualTotal / 12) * 100) / 100;
            const savingsPct = calculateSavingsPercentage(monthlyTotal, annualTotal);

            const result: LocalizedPriceData = {
              monthlyFormatted: formatCurrency(monthlyTotal, currencyCode, country),
              monthlyAmount: monthlyTotal,
              annualFormatted: formatCurrency(annualTotal, currencyCode, country),
              annualAmount: annualTotal,
              monthlyEquivalentFormatted: `${formatCurrency(monthlyEq, currencyCode, country)} / mo`,
              monthlyEquivalentAmount: monthlyEq,
              currencyCode,
              currencySymbol,
              countryCode: country,
              savingsPct,
              rawResponse: preview,
            };

            clientPriceCache[country] = result;
            setData(result);
            setIsLoading(false);
            return;
          }
        } catch (paddleErr) {
          console.warn("Paddle.js PricePreview failed, falling back to API:", paddleErr);
        }
      }

      // 2. Fetch from /api/paddle/prices proxy
      const res = await fetch(`/api/paddle/prices?country=${country}&currency=${targetCurrency}`);
      if (res.ok) {
        const apiData = await res.json();
        const result: LocalizedPriceData = {
          monthlyFormatted: apiData.monthlyFormatted,
          monthlyAmount: apiData.monthlyAmount,
          annualFormatted: apiData.annualFormatted,
          annualAmount: apiData.annualAmount,
          monthlyEquivalentFormatted: apiData.monthlyEquivalentFormatted,
          monthlyEquivalentAmount: apiData.monthlyEquivalentAmount,
          currencyCode: apiData.currencyCode,
          currencySymbol: apiData.currencySymbol,
          countryCode: apiData.countryCode,
          savingsPct: apiData.savingsPct,
          rawResponse: apiData,
        };
        clientPriceCache[country] = result;
        setData(result);
      }
    } catch (err) {
      console.error("Failed to load localized prices:", err);
    } finally {
      setIsLoading(false);
    }
  }, [mockCountry]);

  useEffect(() => {
    let ignore = false;
    async function load() {
      if (!ignore) {
        await fetchPricing();
      }
    }
    load();
    return () => {
      ignore = true;
    };
  }, [fetchPricing]);

  return {
    ...data,
    isLoading,
    mockCountry,
    isMocked: Boolean(mockCountry),
    setMockCountry,
    refetch: fetchPricing,
  };
}
