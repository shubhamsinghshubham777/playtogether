"use client";

import { useEffect, useState, useCallback } from "react";
import { getPaddleInstance } from "@/components/PaddleCheckout";
import {
  COUNTRY_CURRENCY_MAP,
  detectUserCountry,
  formatCurrency,
  calculateSavingsPercentage,
  type LocalizedPriceData,
} from "./pricing";

const PADDLE_MONTHLY_PRICE_ID =
  process.env.NEXT_PUBLIC_PADDLE_MONTHLY_PRICE_ID || "pri_01m02w4z770krsa3sw2ydsskgs";
const PADDLE_ANNUAL_PRICE_ID =
  process.env.NEXT_PUBLIC_PADDLE_ANNUAL_PRICE_ID || "pri_01m02w6w151nd2em52yrpar44y";

// In-memory client-side price cache to eliminate duplicate network calls
const clientPriceCache: Record<string, LocalizedPriceData> = {};

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
  const [mockCountry, setMockCountryState] = useState<string | null>(() => {
    if (typeof window !== "undefined") {
      const urlParams = new URLSearchParams(window.location.search);
      const paramMock = urlParams.get("mock_country") || urlParams.get("country");
      const storedMock = localStorage.getItem("playtogether_mock_country");
      const activeMock = paramMock || storedMock || null;
      return activeMock ? activeMock.toUpperCase() : null;
    }
    return null;
  });

  const setMockCountry = useCallback((country: string | null) => {
    if (country) {
      const upper = country.toUpperCase();
      localStorage.setItem("playtogether_mock_country", upper);
      setMockCountryState(upper);
    } else {
      localStorage.removeItem("playtogether_mock_country");
      setMockCountryState(null);
    }
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("pt_mock_country_changed", { detail: country }));
    }
  }, []);

  // Expose global helper for automated testing and developer console
  useEffect(() => {
    if (typeof window !== "undefined") {
      (window as unknown as { __setMockCountry?: (c: string | null) => void }).__setMockCountry = setMockCountry;
    }
    return () => {
      if (typeof window !== "undefined") {
        delete (window as unknown as { __setMockCountry?: (c: string | null) => void }).__setMockCountry;
      }
    };
  }, [setMockCountry]);

  // Sync when mock country changes in other components
  useEffect(() => {
    const handler = (e: Event) => {
      const customEvent = e as CustomEvent<string | null>;
      setMockCountryState(customEvent.detail ? customEvent.detail.toUpperCase() : null);
    };
    window.addEventListener("pt_mock_country_changed", handler);
    return () => {
      window.removeEventListener("pt_mock_country_changed", handler);
    };
  }, []);

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
          const preview = await paddle.PricePreview({
            items: [
              { priceId: PADDLE_MONTHLY_PRICE_ID, quantity: 1 },
              { priceId: PADDLE_ANNUAL_PRICE_ID, quantity: 1 },
            ],
            address: { countryCode: country },
            currencyCode: targetCurrency as "USD" | "EUR" | "GBP" | "INR" | "CAD" | "AUD" | "JPY",
          });

          if (preview?.data?.details?.lineItems?.length) {
            const lineItems = preview.data.details.lineItems;
            const monthlyItem =
              lineItems.find((item) => item.price?.id === PADDLE_MONTHLY_PRICE_ID) ||
              lineItems[0];
            const annualItem =
              lineItems.find((item) => item.price?.id === PADDLE_ANNUAL_PRICE_ID) ||
              lineItems[1];

            const currencyCode = preview.data.currencyCode || targetCurrency;
            const currencySymbol =
              COUNTRY_CURRENCY_MAP[country]?.symbol ||
              COUNTRY_CURRENCY_MAP[currencyCode]?.symbol ||
              "$";

            const monthlyTotal =
              parseFloat(monthlyItem.totals?.total || monthlyItem.unitTotals?.total || "399") / 100;
            const annualTotal =
              parseFloat(annualItem.totals?.total || annualItem.unitTotals?.total || "2999") / 100;
            const monthlyEq = Math.round((annualTotal / 12) * 100) / 100;
            const savingsPct = calculateSavingsPercentage(monthlyTotal, annualTotal);

            const result: LocalizedPriceData = {
              monthlyFormatted:
                monthlyItem.formattedTotals?.total || formatCurrency(monthlyTotal, currencyCode),
              monthlyAmount: monthlyTotal,
              annualFormatted:
                annualItem.formattedTotals?.total || formatCurrency(annualTotal, currencyCode),
              annualAmount: annualTotal,
              monthlyEquivalentFormatted: `${formatCurrency(monthlyEq, currencyCode)} / mo`,
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
