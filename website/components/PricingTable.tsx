"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { PRICING_TIERS } from "@/lib/constants";
import { PlanCard } from "./PlanCard";
import { GlassPanel } from "./GlassPanel";
import { openPaddleCheckout } from "./PaddleCheckout";
import { openRazorpayCheckout } from "./RazorpayCheckout";
import { createClient } from "@/lib/supabase/client";
import { Globe, Check, Minus } from "lucide-react";
import type { User } from "@supabase/supabase-js";

interface PricingTableProps {
  initialRegion?: "IN" | "INTL";
}

export function PricingTable({ initialRegion = "INTL" }: PricingTableProps) {
  const [billingCycle, setBillingCycle] = useState<"monthly" | "annual">("annual");
  const [region, setRegion] = useState<"IN" | "INTL">(initialRegion);
  const [user, setUser] = useState<User | null>(null);
  const [isLoadingCheckout, setIsLoadingCheckout] = useState(false);
  const router = useRouter();
  const supabase = createClient();

  useEffect(() => {
    async function checkAuth() {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      setUser(user);
    }
    checkAuth();
  }, [supabase]);

  const handleSelectPlan = async (tierKey: string) => {
    if (tierKey === "guest" || tierKey === "free") {
      router.push("/download");
      return;
    }

    if (tierKey === "premium") {
      if (!user) {
        router.push("/auth?redirect=/pricing");
        return;
      }

      setIsLoadingCheckout(true);
      try {
        if (region === "IN") {
          await openRazorpayCheckout({
            plan: billingCycle === "annual" ? "12mo" : "1mo",
            userId: user.id,
            userEmail: user.email,
            userName: user.user_metadata?.full_name,
          });
        } else {
          const priceId =
            billingCycle === "annual"
              ? process.env.PADDLE_ANNUAL_PRICE_ID || "pri_annual_default"
              : process.env.PADDLE_MONTHLY_PRICE_ID || "pri_monthly_default";

          await openPaddleCheckout({
            priceId,
            userId: user.id,
            userEmail: user.email,
          });
        }
      } finally {
        setIsLoadingCheckout(false);
      }
    }
  };

  const isIndia = region === "IN";
  const premiumPrice = isIndia
    ? billingCycle === "annual"
      ? "₹999"
      : "₹149"
    : billingCycle === "annual"
    ? "$29.99"
    : "$3.99";

  const premiumSubPrice = isIndia
    ? billingCycle === "annual"
      ? "₹83 / mo (Billed annually — Save ₹789)"
      : "Prepaid 1-Month Pass"
    : billingCycle === "annual"
    ? "$2.49 / mo (Billed annually — Save 37%)"
    : "Billed monthly. Cancel anytime.";

  return (
    <div className="space-y-12">
      {/* Controls Bar: Billing Toggle & Region Switch */}
      <div className="flex flex-col sm:flex-row items-center justify-center gap-6">
        {/* Monthly / Annual Toggle */}
        <div className="p-1 rounded-2xl bg-[#141024] border border-purple-500/20 flex items-center shadow-inner">
          <button
            onClick={() => setBillingCycle("monthly")}
            className={`px-5 py-2 rounded-xl text-sm font-semibold transition-all ${
              billingCycle === "monthly"
                ? "btn-primary-gradient text-white shadow-md shadow-purple-900/40"
                : "text-gray-400 hover:text-white"
            }`}
          >
            Monthly Billing
          </button>
          <button
            onClick={() => setBillingCycle("annual")}
            className={`px-5 py-2 rounded-xl text-sm font-semibold transition-all flex items-center gap-2 ${
              billingCycle === "annual"
                ? "btn-primary-gradient text-white shadow-md shadow-purple-900/40"
                : "text-gray-400 hover:text-white"
            }`}
          >
            <span>Annual Billing</span>
            <span className="text-[10px] uppercase font-bold tracking-wider px-2 py-0.5 rounded-full bg-amber-400/20 text-amber-300 border border-amber-400/30">
              Save {isIndia ? "44%" : "37%"}
            </span>
          </button>
        </div>

        {/* Currency / Region Selector */}
        <div className="flex items-center gap-2 bg-[#141024] px-3.5 py-1.5 rounded-xl border border-purple-500/20 text-xs text-gray-300">
          <Globe className="w-4 h-4 text-purple-400" />
          <span className="text-gray-400">Region:</span>
          <select
            value={region}
            onChange={(e) => setRegion(e.target.value as "IN" | "INTL")}
            className="bg-transparent text-purple-200 font-semibold focus:outline-hidden cursor-pointer"
          >
            <option value="INTL" className="bg-[#161226] text-white">
              International (USD - Paddle)
            </option>
            <option value="IN" className="bg-[#161226] text-white">
              India (INR - Razorpay)
            </option>
          </select>
        </div>
      </div>

      {/* Pricing Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
        {/* Guest Tier */}
        <PlanCard
          name={PRICING_TIERS.guest.name}
          badge={PRICING_TIERS.guest.badge}
          price="$0"
          periodText="forever"
          description={PRICING_TIERS.guest.description}
          features={PRICING_TIERS.guest.features}
          ctaText={PRICING_TIERS.guest.cta}
          onSelect={() => handleSelectPlan("guest")}
        />

        {/* Free Tier */}
        <PlanCard
          name={PRICING_TIERS.free.name}
          badge={PRICING_TIERS.free.badge}
          price="$0"
          periodText="with Google sign-in"
          description={PRICING_TIERS.free.description}
          features={PRICING_TIERS.free.features}
          ctaText={PRICING_TIERS.free.cta}
          isPopular
          onSelect={() => handleSelectPlan("free")}
        />

        {/* Premium Tier */}
        <PlanCard
          name={PRICING_TIERS.premium.name}
          badge={PRICING_TIERS.premium.badge}
          price={premiumPrice}
          periodText={billingCycle === "annual" ? "/year" : "/month"}
          subPrice={premiumSubPrice}
          description={PRICING_TIERS.premium.description}
          features={PRICING_TIERS.premium.features}
          ctaText={user ? "Upgrade to Premium" : "Sign in to Subscribe"}
          isPremium
          isLoading={isLoadingCheckout}
          onSelect={() => handleSelectPlan("premium")}
        />
      </div>

      {/* Feature Comparison Matrix Table */}
      <div className="pt-12">
        <div className="text-center mb-8">
          <h3 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            Compare Plan Capabilities
          </h3>
          <p className="text-sm text-gray-400 mt-1">
            Detailed breakdown of room limits, audio/video capabilities, and perks.
          </p>
        </div>

        <GlassPanel className="overflow-x-auto p-0 border border-purple-500/20">
          <table className="w-full text-left text-sm text-gray-300">
            <thead className="bg-[#120E22] text-xs uppercase font-bold text-purple-300/80 border-b border-purple-500/20">
              <tr>
                <th className="p-4 sm:p-5">Feature</th>
                <th className="p-4 sm:p-5">Guest</th>
                <th className="p-4 sm:p-5 text-purple-200">Free</th>
                <th className="p-4 sm:p-5 text-amber-300">Premium</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              <tr>
                <td className="p-4 sm:p-5 font-semibold text-white">Active Rooms</td>
                <td className="p-4 sm:p-5">1 room</td>
                <td className="p-4 sm:p-5">4 rooms</td>
                <td className="p-4 sm:p-5 text-amber-300 font-bold">20 persistent rooms</td>
              </tr>
              <tr>
                <td className="p-4 sm:p-5 font-semibold text-white">Members per Room</td>
                <td className="p-4 sm:p-5">4 members</td>
                <td className="p-4 sm:p-5">8 members</td>
                <td className="p-4 sm:p-5 text-amber-300 font-bold">16 members</td>
              </tr>
              <tr>
                <td className="p-4 sm:p-5 font-semibold text-white">Session Length</td>
                <td className="p-4 sm:p-5">60 minutes</td>
                <td className="p-4 sm:p-5">4 hours + 1h bonus</td>
                <td className="p-4 sm:p-5 text-amber-300 font-bold">Up to 24 hours</td>
              </tr>
              <tr>
                <td className="p-4 sm:p-5 font-semibold text-white">Voice & Video Facecams</td>
                <td className="p-4 sm:p-5 text-gray-500"><Minus className="w-4 h-4" /></td>
                <td className="p-4 sm:p-5 text-purple-300">Voice only</td>
                <td className="p-4 sm:p-5 text-amber-300 font-bold">HD Video + Voice</td>
              </tr>
              <tr>
                <td className="p-4 sm:p-5 font-semibold text-white">Room Nap & Resume</td>
                <td className="p-4 sm:p-5 text-gray-500">Deleted immediately</td>
                <td className="p-4 sm:p-5">Naps for 24 hours</td>
                <td className="p-4 sm:p-5 text-amber-300 font-bold">Permanent memory</td>
              </tr>
              <tr>
                <td className="p-4 sm:p-5 font-semibold text-white">Animated Emoji Reactions</td>
                <td className="p-4 sm:p-5">8 standard</td>
                <td className="p-4 sm:p-5">8 standard</td>
                <td className="p-4 sm:p-5 text-amber-300 font-bold">24 Lottie animated</td>
              </tr>
              <tr>
                <td className="p-4 sm:p-5 font-semibold text-white">Media Support (Local + YouTube)</td>
                <td className="p-4 sm:p-5"><Check className="w-4 h-4 text-emerald-400" /></td>
                <td className="p-4 sm:p-5"><Check className="w-4 h-4 text-emerald-400" /></td>
                <td className="p-4 sm:p-5"><Check className="w-4 h-4 text-emerald-400" /></td>
              </tr>
            </tbody>
          </table>
        </GlassPanel>
      </div>
    </div>
  );
}
