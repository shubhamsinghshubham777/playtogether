"use client";

import { GlassPanel } from "./GlassPanel";
import { PTButton } from "./PTButton";
import { LocationDebugSwitcher } from "./LocationDebugSwitcher";
import { usePricing } from "@/lib/usePricing";
import { Check, ArrowRight, Loader2 } from "lucide-react";

export function TierPreviewSection() {
  const { monthlyFormatted, isLoading } = usePricing();

  return (
    <section id="features" className="relative py-20 bg-[#0A0814] border-t border-purple-500/10">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-6 mb-12">
          <div>
            <h2 className="text-3xl sm:text-4xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
              Simple, transparent tiers.
            </h2>
            <p className="text-sm text-gray-400 mt-1">
              Start completely free. Upgrade whenever you need persistent rooms and video facecams.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <LocationDebugSwitcher />
            <PTButton
              href="/pricing"
              variant="outline"
              size="md"
              rightIcon={<ArrowRight className="w-4 h-4" />}
            >
              View Full Pricing &amp; Details
            </PTButton>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {/* Guest Tier */}
          <GlassPanel className="p-6 space-y-4">
            <div className="flex items-center justify-between">
              <span className="font-bold text-lg text-white font-[family-name:var(--font-space-grotesk)]">
                Guest
              </span>
              <span className="text-xs font-mono text-gray-400">Free</span>
            </div>
            <p className="text-xs text-gray-400">
              1 room • 4 members • 60 mins • No sign-in
            </p>
            <ul className="text-xs text-gray-300 space-y-2 pt-2 border-t border-white/5">
              <li className="flex items-center gap-2">
                <Check className="w-3.5 h-3.5 text-purple-400" /> Local &amp; YouTube Sync
              </li>
              <li className="flex items-center gap-2">
                <Check className="w-3.5 h-3.5 text-purple-400" /> Text Chat &amp; Reactions
              </li>
            </ul>
          </GlassPanel>

          {/* Free Tier */}
          <GlassPanel className="p-6 space-y-4 border-purple-400/30 bg-[#161226]/80">
            <div className="flex items-center justify-between">
              <span className="font-bold text-lg text-white font-[family-name:var(--font-space-grotesk)]">
                Free
              </span>
              <span className="text-xs font-mono text-purple-300 font-bold">
                Google Auth
              </span>
            </div>
            <p className="text-xs text-gray-400">
              4 rooms • 8 members • 4 hours • Voice chat
            </p>
            <ul className="text-xs text-gray-300 space-y-2 pt-2 border-t border-white/5">
              <li className="flex items-center gap-2">
                <Check className="w-3.5 h-3.5 text-purple-400" /> Voice Facecams
              </li>
              <li className="flex items-center gap-2">
                <Check className="w-3.5 h-3.5 text-purple-400" /> 24h Room Dormancy Sleep
              </li>
            </ul>
          </GlassPanel>

          {/* Premium Tier */}
          <GlassPanel className="p-6 space-y-4 border-amber-400/40 bg-[#1A1428]/85">
            <div className="flex items-center justify-between">
              <span className="font-bold text-lg text-amber-300 font-[family-name:var(--font-space-grotesk)]">
                Premium
              </span>
              {isLoading ? (
                <div className="flex items-center gap-1.5 text-xs font-mono text-amber-400 font-bold py-0.5">
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  <span>Loading price...</span>
                </div>
              ) : (
                <span
                  id="features-premium-price"
                  className="text-xs font-mono text-amber-400 font-bold animate-in fade-in duration-200"
                >
                  {monthlyFormatted}/mo
                </span>
              )}
            </div>
            <p className="text-xs text-gray-400">
              20 persistent rooms • 16 members • 24h • Video Cams
            </p>
            <ul className="text-xs text-gray-300 space-y-2 pt-2 border-t border-white/5">
              <li className="flex items-center gap-2">
                <Check className="w-3.5 h-3.5 text-amber-400" /> Video &amp; Voice Facecams
              </li>
              <li className="flex items-center gap-2">
                <Check className="w-3.5 h-3.5 text-amber-400" /> 24 Animated Emoji Reactions
              </li>
            </ul>
          </GlassPanel>
        </div>
      </div>
    </section>
  );
}
