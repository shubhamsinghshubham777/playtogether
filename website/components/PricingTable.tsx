"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { PRICING_TIERS } from "@/lib/constants";
import { PlanCard } from "./PlanCard";
import { GlassPanel } from "./GlassPanel";
import { LocationDebugSwitcher } from "./LocationDebugSwitcher";
import { openPaddleCheckout } from "./PaddleCheckout";
import { createClient } from "@/lib/supabase/client";
import { usePricing } from "@/lib/usePricing";
import { Check, Minus, Loader2 } from "lucide-react";
import type { User } from "@supabase/supabase-js";

export function PricingTable() {
  const [billingCycle, setBillingCycle] = useState<"monthly" | "annual">("annual");
  const [user, setUser] = useState<User | null>(null);
  const [isPremium, setIsPremium] = useState(false);
  const [isLoadingCheckout, setIsLoadingCheckout] = useState(false);
  const router = useRouter();
  const supabase = createClient();
  const {
    monthlyFormatted,
    annualFormatted,
    monthlyEquivalentFormatted,
    savingsPct,
    isLoading: isPriceLoading,
  } = usePricing();

  useEffect(() => {
    let ignore = false;
    async function checkAuth() {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (ignore) return;
      setUser(user);
      if (user) {
        try {
          const { data: entData } = await supabase.rpc("my_entitlement");
          if (ignore) return;
          if (entData) {
            const ent = Array.isArray(entData) ? entData[0] : entData;
            setIsPremium(ent?.tier === "premium");
          } else {
            const { data: sub } = await supabase
              .from("subscriptions")
              .select("tier, current_period_end")
              .eq("user_id", user.id)
              .maybeSingle();
            if (ignore) return;
            if (sub?.tier === "premium") {
              const isExpired =
                sub.current_period_end &&
                new Date(sub.current_period_end) < new Date();
              setIsPremium(!isExpired);
            }
          }
        } catch {
          if (!ignore) setIsPremium(false);
        }
      }
    }
    checkAuth();
    return () => {
      ignore = true;
    };
  }, [supabase]);

  const handleSelectPlan = async (tierKey: string) => {
    if (tierKey === "guest" || tierKey === "free") {
      router.push("/download");
      return;
    }

    if (tierKey === "premium") {
      if (isPremium) {
        router.push("/account");
        return;
      }

      if (!user) {
        router.push("/auth?redirect=/pricing");
        return;
      }

      setIsLoadingCheckout(true);
      try {
        const priceId =
          billingCycle === "annual"
            ? process.env.NEXT_PUBLIC_PADDLE_ANNUAL_PRICE_ID ||
              process.env.PADDLE_ANNUAL_PRICE_ID ||
              "pri_annual_default"
            : process.env.NEXT_PUBLIC_PADDLE_MONTHLY_PRICE_ID ||
              process.env.PADDLE_MONTHLY_PRICE_ID ||
              "pri_monthly_default";

        await openPaddleCheckout({
          priceId,
          userId: user.id,
          userEmail: user.email,
        });
      } finally {
        setIsLoadingCheckout(false);
      }
    }
  };

  const premiumPrice = isPriceLoading ? (
    <span className="inline-flex items-center gap-2 py-1 text-2xl font-mono text-amber-400 font-bold">
      <Loader2 className="w-6 h-6 animate-spin" />
    </span>
  ) : billingCycle === "annual" ? (
    annualFormatted
  ) : (
    monthlyFormatted
  );

  const premiumSubPrice = isPriceLoading
    ? "Fetching live pricing from Paddle..."
    : billingCycle === "annual"
    ? `${monthlyEquivalentFormatted} (Billed annually — Save ${savingsPct})`
    : "Billed monthly. Cancel anytime.";

  return (
    <div className="space-y-12">
      {/* Controls Bar: Billing Toggle & Debug Switcher */}
      <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
        {/* Monthly / Annual Toggle */}
        <div className="p-1 rounded-2xl bg-[#141024] border border-purple-500/20 flex items-center shadow-inner">
          <button
            onClick={() => setBillingCycle("monthly")}
            className={`px-5 py-2 rounded-xl text-sm font-semibold transition-all cursor-pointer ${
              billingCycle === "monthly"
                ? "btn-primary-gradient text-white shadow-md shadow-purple-900/40"
                : "text-gray-400 hover:text-white"
            }`}
          >
            Monthly Billing
          </button>
          <button
            onClick={() => setBillingCycle("annual")}
            className={`px-5 py-2 rounded-xl text-sm font-semibold transition-all flex items-center gap-2 cursor-pointer ${
              billingCycle === "annual"
                ? "btn-primary-gradient text-white shadow-md shadow-purple-900/40"
                : "text-gray-400 hover:text-white"
            }`}
          >
            <span>Annual Billing</span>
            <span className="text-[10px] uppercase font-bold tracking-wider px-2 py-0.5 rounded-full bg-amber-400/20 text-amber-300 border border-amber-400/30">
              Save {savingsPct}
            </span>
          </button>
        </div>

        <LocationDebugSwitcher />
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
          badge={isPremium ? "Active Plan" : PRICING_TIERS.premium.badge}
          price={premiumPrice}
          periodText={billingCycle === "annual" ? "/year" : "/month"}
          subPrice={premiumSubPrice}
          description={PRICING_TIERS.premium.description}
          features={PRICING_TIERS.premium.features}
          ctaText={
            isPremium
              ? "Manage Subscription"
              : user
              ? "Upgrade to Premium"
              : "Sign in to Subscribe"
          }
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
