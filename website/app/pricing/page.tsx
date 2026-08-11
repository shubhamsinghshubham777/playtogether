import type { Metadata } from "next";
import { headers } from "next/headers";
import { PricingTable } from "@/components/PricingTable";
import { FAQAccordion } from "@/components/FAQAccordion";
import { getRegionFromCountry } from "@/lib/geo";

export const metadata: Metadata = {
  title: "Pricing & Plans — PlayTogether Premium",
  description:
    "Upgrade to PlayTogether Premium for 20 persistent rooms, 16 members, 24-hour sessions, HD video facecams, and extended emoji reactions.",
};

export default async function PricingPage() {
  const headerList = await headers();
  const countryCode = headerList.get("x-vercel-ip-country");
  const initialRegion = getRegionFromCountry(countryCode);

  const pricingFaqs = [
    {
      q: "Can I try PlayTogether before paying?",
      a: "Yes! Both our Guest and Free tiers are 100% free and fully functional. Free tier includes 4-hour sessions, 8 members, voice chat, and 24-hour room memory."
    },
    {
      q: "What payment methods do you accept?",
      a: "For international users, we process payments securely via Paddle (Credit Cards, PayPal, Apple Pay, Google Pay). In India, we accept UPI, Credit/Debit Cards, and Netbanking via Razorpay prepaid passes."
    },
    {
      q: "Can I cancel my subscription anytime?",
      a: "Yes, you can cancel anytime from your Account page. Your premium benefits will remain active until the end of your prepaid billing period without any unexpected charges."
    },
    {
      q: "Do I need an account to subscribe?",
      a: "Yes, you must sign in with your Google account on the website to purchase Premium. This ensures your purchase links directly to your PlayTogether desktop app identity."
    },
    {
      q: "What happens to my rooms if my subscription expires?",
      a: "Your persistent rooms transition gracefully to standard Free tier limits with a 7-day grace period. No room data or history is deleted abruptly."
    }
  ];

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-16">
      {/* Background Ambient Glow */}
      <div className="glow-blob-purple top-0 left-1/2 -translate-x-1/2 opacity-30" />

      {/* Header */}
      <div className="text-center max-w-3xl mx-auto space-y-4">
        <h1 className="text-4xl sm:text-6xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Simple, transparent <span className="text-gradient-brand">pricing.</span>
        </h1>
        <p className="text-lg text-gray-300">
          Unlock the ultimate theater experience with HD video facecams, 16-member rooms, and persistent memory.
        </p>
      </div>

      {/* Pricing Table (Interactive Component) */}
      <PricingTable initialRegion={initialRegion} />

      {/* Pricing FAQ Section */}
      <div className="max-w-4xl mx-auto pt-12 space-y-8">
        <div className="text-center space-y-2">
          <h2 className="text-2xl sm:text-3xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            Frequently Asked Questions
          </h2>
          <p className="text-sm text-gray-400">
            Have questions about billing or subscriptions? We&apos;ve got answers.
          </p>
        </div>

        <FAQAccordion items={pricingFaqs} />
      </div>
    </div>
  );
}
