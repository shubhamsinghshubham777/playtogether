import type { Metadata } from "next";
import { GlassPanel } from "@/components/GlassPanel";
import { SITE_CONFIG } from "@/lib/constants";
import { RefreshCcw } from "lucide-react";

export const metadata: Metadata = {
  title: "Refund Policy (14-Day Money-Back Guarantee)",
  description: "SyncTogether 14-day no-questions-asked refund policy for Premium subscriptions.",
};

export default function RefundPage() {
  const lastUpdated = "August 15, 2026";

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-12">
      <div className="space-y-3 text-center sm:text-left">
        <span className="text-xs font-mono text-purple-400 font-bold uppercase tracking-wider">
          Customer Guarantee
        </span>
        <h1 className="text-4xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Refund Policy
        </h1>
        <p className="text-xs text-gray-400 font-mono">
          Last Updated: {lastUpdated}
        </p>
      </div>

      <GlassPanel className="p-8 sm:p-10 space-y-8 text-sm text-gray-300 leading-relaxed border-purple-500/20">
        <section className="space-y-3">
          <div className="p-4 rounded-xl bg-amber-500/10 border border-amber-400/20 space-y-2 text-amber-200 text-xs">
            <div className="flex items-center gap-2 font-bold text-white text-sm">
              <RefreshCcw className="w-4 h-4 text-amber-400" />
              <span>14-Day Money-Back Guarantee</span>
            </div>
            <p>
              We want you to love SyncTogether. If you are not completely satisfied with your first purchase of SyncTogether Premium, you can request a full refund within 14 days of your initial payment — no questions asked.
            </p>
          </div>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            1. Requesting a Refund
          </h2>
          <p>
            All subscriptions are processed securely through our authorized Merchant of Record.
          </p>
          <ul className="space-y-1.5 text-xs text-gray-400 list-disc list-inside">
            <li>To request a refund, email <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="text-purple-300 underline">{SITE_CONFIG.supportEmail}</a> with your account email address.</li>
            <li>Refunds are processed directly back to your original payment method (Credit/Debit Card, PayPal, Apple Pay, Google Pay, UPI, etc.) within 5–7 business days.</li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            3. After 14 Days
          </h2>
          <p>
            Payments made after the 14-day initial guarantee window are non-refundable. However, you can cancel your subscription at any time; your Premium perks will remain available until the conclusion of your current billing period.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            4. Abuse Protection
          </h2>
          <p>
            We reserve the right to decline refund requests in cases of suspected fraudulent behavior or repeated subscribe-and-refund cycles.
          </p>
        </section>
      </GlassPanel>
    </div>
  );
}
