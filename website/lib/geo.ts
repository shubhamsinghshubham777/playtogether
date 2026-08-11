export type Region = "IN" | "INTL";

export interface RegionPricing {
  currency: string;
  currencySymbol: string;
  monthlyPrice: string;
  annualPrice: string;
  annualMonthlyEquivalent: string;
  savingsText: string;
  isIndia: boolean;
}

export function getRegionFromCountry(countryCode?: string | null): Region {
  if (!countryCode) return "INTL";
  return countryCode.toUpperCase() === "IN" ? "IN" : "INTL";
}

export function getPricingForRegion(region: Region): RegionPricing {
  if (region === "IN") {
    return {
      currency: "INR",
      currencySymbol: "₹",
      monthlyPrice: "₹149",
      annualPrice: "₹999",
      annualMonthlyEquivalent: "₹83",
      savingsText: "Save ₹789 / yr (44% off)",
      isIndia: true,
    };
  }

  return {
    currency: "USD",
    currencySymbol: "$",
    monthlyPrice: "$3.99",
    annualPrice: "$29.99",
    annualMonthlyEquivalent: "$2.49",
    savingsText: "Save $17.89 / yr (37% off)",
    isIndia: false,
  };
}
