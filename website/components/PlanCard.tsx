import React from "react";
import { GlassPanel } from "./GlassPanel";
import { PTButton } from "./PTButton";
import { Check, Sparkles } from "lucide-react";

interface PlanCardProps {
  name: string;
  badge?: string;
  price: React.ReactNode;
  subPrice?: React.ReactNode;
  periodText?: string;
  description: string;
  features: string[];
  ctaText: string;
  isPopular?: boolean;
  isPremium?: boolean;
  isLoading?: boolean;
  onSelect: () => void;
}

export function PlanCard({
  name,
  badge,
  price,
  subPrice,
  periodText = "/month",
  description,
  features,
  ctaText,
  isPopular = false,
  isPremium = false,
  isLoading = false,
  onSelect,
}: PlanCardProps) {
  return (
    <GlassPanel
      hoverEffect
      glow={isPremium ? "gold" : isPopular ? "purple" : "none"}
      className={`flex flex-col justify-between relative ${
        isPremium
          ? "border-amber-400/40 bg-[#1A1428]/85"
          : isPopular
          ? "border-purple-400/40 bg-[#161226]/85"
          : "border-purple-500/15"
      }`}
    >
      {/* Top Badge */}
      {badge && (
        <div className="absolute top-4 right-4">
          <span
            className={`text-[11px] font-bold tracking-wider uppercase px-2.5 py-1 rounded-full border ${
              isPremium
                ? "bg-amber-400/15 text-amber-300 border-amber-400/30 shadow-sm"
                : isPopular
                ? "bg-purple-500/20 text-purple-200 border-purple-400/30"
                : "bg-white/5 text-gray-300 border-white/10"
            }`}
          >
            {badge}
          </span>
        </div>
      )}

      {/* Plan Header */}
      <div>
        <div className="space-y-1 mb-4">
          <h3 className="text-2xl font-bold tracking-tight text-white font-[family-name:var(--font-space-grotesk)]">
            {name}
          </h3>
          <p className="text-xs text-gray-400 leading-relaxed min-h-[36px]">
            {description}
          </p>
        </div>

        {/* Pricing Display */}
        <div className="mb-6 pt-2 border-t border-white/5">
          <div className="flex items-baseline gap-1.5">
            <span
              className={`text-4xl font-extrabold tracking-tight font-[family-name:var(--font-space-grotesk)] ${
                isPremium ? "text-gradient-gold" : "text-white"
              }`}
            >
              {price}
            </span>
            {periodText && (
              <span className="text-xs font-medium text-gray-400">
                {periodText}
              </span>
            )}
          </div>
          {subPrice && (
            <p className="text-xs text-purple-300/80 font-mono mt-1">
              {subPrice}
            </p>
          )}
        </div>

        {/* Features Checklist */}
        <div className="space-y-3 mb-8">
          <p className="text-xs font-bold uppercase tracking-wider text-gray-400">
            What&apos;s included:
          </p>
          <ul className="space-y-2.5 text-sm">
            {features.map((feature, idx) => (
              <li key={idx} className="flex items-start gap-2.5 text-gray-300">
                <div
                  className={`mt-0.5 p-0.5 rounded-full ${
                    isPremium
                      ? "bg-amber-400/20 text-amber-300"
                      : "bg-purple-500/20 text-purple-300"
                  }`}
                >
                  <Check className="w-3.5 h-3.5" />
                </div>
                <span className="text-xs leading-tight">{feature}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>

      {/* CTA Button */}
      <PTButton
        variant={isPremium ? "gold" : isPopular ? "primary" : "secondary"}
        size="md"
        className="w-full"
        isLoading={isLoading}
        onClick={onSelect}
        leftIcon={isPremium ? <Sparkles className="w-4 h-4" /> : undefined}
      >
        {ctaText}
      </PTButton>
    </GlassPanel>
  );
}
