"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Image from "next/image";
import { GlassPanel } from "@/components/GlassPanel";
import { PTButton } from "@/components/PTButton";
import { createClient } from "@/lib/supabase/client";
import type { User } from "@supabase/supabase-js";
import confetti from "canvas-confetti";
import {
  Sparkles,
  ShieldCheck,
  Layers,
  Users,
  Video,
  Clock,
  ExternalLink,
  LogOut,
  Download,
  CheckCircle2,
  RefreshCw,
} from "lucide-react";

interface EntitlementData {
  tier: "guest" | "free" | "premium";
  max_live_rooms: number;
  max_members: number;
  max_session_minutes: number;
  max_total_session_minutes: number;
  av_level: string;
  persistent_room_cap: number;
  dormant_hours: number;
  free_extension_minutes: number;
}

interface SubscriptionData {
  tier: string;
  current_period_end: string | null;
  source: string;
  updated_at: string;
}

function AccountDashboard() {
  const [user, setUser] = useState<User | null>(null);
  const [entitlement, setEntitlement] = useState<EntitlementData | null>(null);
  const [subscription, setSubscription] = useState<SubscriptionData | null>(null);
  const [loading, setLoading] = useState(true);
  const [verifying, setVerifying] = useState(false);
  const [pollCount, setPollCount] = useState(0);
  const [isLoggingOut, setIsLoggingOut] = useState(false);

  const router = useRouter();
  const searchParams = useSearchParams();
  const isSubscribedRedirect = searchParams.get("subscribed") === "true";
  const supabase = createClient();

  useEffect(() => {
    let ignore = false;

    async function loadData() {
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser();

        if (!user) {
          router.push("/auth?redirect=/account");
          return;
        }
        if (!ignore) setUser(user);

        // Call my_entitlement RPC
        const { data: entData, error: entError } = await supabase.rpc(
          "my_entitlement"
        );
        if (!ignore) {
          if (!entError && entData) {
            const ent = Array.isArray(entData) ? entData[0] : entData;
            setEntitlement(ent);
          } else {
            setEntitlement({
              tier: "free",
              max_live_rooms: 4,
              max_members: 8,
              max_session_minutes: 240,
              max_total_session_minutes: 240,
              av_level: "voice",
              persistent_room_cap: 0,
              dormant_hours: 24,
              free_extension_minutes: 60,
            });
          }
        }

        // Query subscriptions table
        const { data: subData } = await supabase
          .from("subscriptions")
          .select("*")
          .eq("user_id", user.id)
          .maybeSingle();

        if (!ignore && subData) {
          setSubscription(subData);
        }
      } catch (err) {
        console.error("Failed to load user account data:", err);
      } finally {
        if (!ignore) setLoading(false);
      }
    }

    loadData();

    return () => {
      ignore = true;
    };
  }, [router, supabase]);

  // Handle post-purchase verification & celebration
  useEffect(() => {
    if (!isSubscribedRedirect) return;

    try {
      confetti({
        particleCount: 100,
        spread: 70,
        origin: { y: 0.6 },
        colors: ["#8B5CF6", "#C084FC", "#FBBF24", "#22D3EE"],
      });
    } catch {
      // ignore confetti errors
    }

    if (entitlement && entitlement.tier !== "premium" && pollCount < 5) {
      const timer = setTimeout(async () => {
        setVerifying(true);
        const { data: entData } = await supabase.rpc("my_entitlement");
        if (entData) {
          const ent = Array.isArray(entData) ? entData[0] : entData;
          setEntitlement(ent);
          if (ent?.tier === "premium") {
            setVerifying(false);
          }
        }
        setPollCount((prev) => prev + 1);
      }, 3000);
      return () => clearTimeout(timer);
    }
  }, [isSubscribedRedirect, entitlement, pollCount, supabase]);

  const handleSignOut = async () => {
    setIsLoggingOut(true);
    await supabase.auth.signOut();
    router.push("/");
  };

  const handleExportData = () => {
    const exportData = {
      profile: {
        id: user?.id,
        email: user?.email,
        name: user?.user_metadata?.full_name,
        created_at: user?.created_at,
      },
      entitlement,
      subscription,
      exported_at: new Date().toISOString(),
    };

    const blob = new Blob([JSON.stringify(exportData, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `playtogether-data-${user?.id?.slice(0, 8)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  if (loading) {
    return (
      <div className="max-w-4xl mx-auto py-24 px-4 text-center space-y-4">
        <div className="w-10 h-10 border-2 border-purple-500 border-t-transparent rounded-full animate-spin mx-auto" />
        <p className="text-sm text-gray-400">Loading your account details...</p>
      </div>
    );
  }

  const isPremium = entitlement?.tier === "premium";

  return (
    <div className="relative py-12 md:py-16 px-4 sm:px-6 lg:px-8 max-w-5xl mx-auto space-y-8">
      {/* Background Glow */}
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-30" />

      {/* Purchase Success / Verification Banner */}
      {isSubscribedRedirect && (
        <GlassPanel
          glow="gold"
          className="p-6 border-amber-400/40 bg-[#1F172E] space-y-2 animate-in fade-in slide-in-from-top-4 duration-300"
        >
          <div className="flex items-center gap-3">
            <CheckCircle2 className="w-6 h-6 text-amber-300 shrink-0" />
            <div>
              <h3 className="text-lg font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Welcome to PlayTogether Premium! 🎉
              </h3>
              <p className="text-xs text-amber-200/80">
                {verifying
                  ? "Activating your subscription across our network... checking status."
                  : "Your subscription is active! All premium benefits are enabled on your account."}
              </p>
            </div>
            {verifying && (
              <RefreshCw className="w-4 h-4 text-amber-300 animate-spin ml-auto" />
            )}
          </div>
        </GlassPanel>
      )}

      {/* Account Overview Header */}
      <GlassPanel className="p-8 space-y-6 border-purple-500/20">
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
          <div className="flex items-center gap-4">
            {user?.user_metadata?.avatar_url ? (
              <Image
                src={user.user_metadata.avatar_url}
                alt={user.user_metadata?.full_name || "Avatar"}
                width={64}
                height={64}
                className="w-16 h-16 rounded-2xl border-2 border-purple-400/40 shadow-lg"
              />
            ) : (
              <div className="w-16 h-16 rounded-2xl bg-purple-600 flex items-center justify-center text-2xl font-bold text-white shadow-lg">
                {user?.email?.charAt(0).toUpperCase() || "U"}
              </div>
            )}
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                  {user?.user_metadata?.full_name || "PlayTogether User"}
                </h1>
                <span
                  className={`text-xs font-bold font-mono uppercase px-2.5 py-0.5 rounded-full border ${
                    isPremium
                      ? "bg-amber-400/20 text-amber-300 border-amber-400/40"
                      : "bg-purple-500/20 text-purple-300 border-purple-400/30"
                  }`}
                >
                  {isPremium ? "★ PREMIUM" : "FREE TIER"}
                </span>
              </div>
              <p className="text-xs text-gray-400 mt-1">{user?.email}</p>
            </div>
          </div>

          <PTButton
            onClick={handleSignOut}
            variant="ghost"
            size="sm"
            isLoading={isLoggingOut}
            leftIcon={<LogOut className="w-4 h-4" />}
          >
            Sign Out
          </PTButton>
        </div>
      </GlassPanel>

      {/* Subscription & Entitlements Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Current Plan Card (2 cols) */}
        <GlassPanel
          glow={isPremium ? "gold" : "purple"}
          className={`md:col-span-2 p-8 space-y-6 flex flex-col justify-between ${
            isPremium ? "border-amber-400/40 bg-[#1A1428]" : "border-purple-500/20"
          }`}
        >
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <span className="text-xs font-bold uppercase tracking-wider text-purple-300 font-mono">
                  Current Plan
                </span>
                <h2 className="text-3xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)] mt-1">
                  PlayTogether {isPremium ? "Premium" : "Free"}
                </h2>
              </div>
              {isPremium ? (
                <Sparkles className="w-8 h-8 text-amber-400" />
              ) : (
                <Layers className="w-8 h-8 text-purple-400" />
              )}
            </div>

            {/* Plan Details */}
            {isPremium ? (
              <div className="p-4 rounded-xl bg-amber-500/10 border border-amber-400/20 space-y-2 text-xs text-amber-200">
                <p className="font-semibold text-white flex items-center gap-1.5">
                  <ShieldCheck className="w-4 h-4 text-amber-400" />
                  <span>Subscription Active ({subscription?.source || "Paddle / Razorpay"})</span>
                </p>
                {subscription?.current_period_end && (
                  <p className="text-gray-300">
                    Next billing / renewal date:{" "}
                    <strong>
                      {new Date(
                        subscription.current_period_end
                      ).toLocaleDateString(undefined, {
                        year: "numeric",
                        month: "long",
                        day: "numeric",
                      })}
                    </strong>
                  </p>
                )}
                {subscription?.source === "razorpay" && (
                  <p className="text-[11px] text-gray-400">
                    Indian prepaid pass. To extend or renew your pass, purchase a new term from the pricing page.
                  </p>
                )}
              </div>
            ) : (
              <div className="p-4 rounded-xl bg-purple-500/10 border border-purple-400/20 space-y-2 text-xs text-purple-200">
                <p className="text-gray-300">
                  You are currently on the Free tier. Upgrade to unlock 20 persistent rooms, 16 members, and HD video facecams.
                </p>
              </div>
            )}
          </div>

          <div className="pt-4 flex flex-wrap items-center gap-4">
            {isPremium ? (
              subscription?.source === "paddle" ? (
                <a
                  href="https://checkout.paddle.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-amber-400/20 hover:bg-amber-400/30 text-amber-300 text-xs font-semibold border border-amber-400/40 transition-colors"
                >
                  <span>Manage in Paddle Portal</span>
                  <ExternalLink className="w-3.5 h-3.5" />
                </a>
              ) : null
            ) : (
              <PTButton
                href="/pricing"
                variant="gold"
                size="md"
                leftIcon={<Sparkles className="w-4 h-4" />}
              >
                Upgrade to Premium
              </PTButton>
            )}
          </div>
        </GlassPanel>

        {/* Live Entitlements Box */}
        <GlassPanel className="p-6 space-y-4 border-purple-500/20 flex flex-col justify-between">
          <div className="space-y-3">
            <h3 className="text-xs font-bold uppercase tracking-wider text-gray-400 font-mono">
              Account Caps &amp; Quotas
            </h3>
            <ul className="space-y-3 text-xs text-gray-300">
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Layers className="w-3.5 h-3.5 text-purple-400" /> Active Rooms
                </span>
                <span className="font-bold text-white">
                  {entitlement?.max_live_rooms ?? 4}
                </span>
              </li>
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Users className="w-3.5 h-3.5 text-purple-400" /> Max Members
                </span>
                <span className="font-bold text-white">
                  {entitlement?.max_members ?? 8}
                </span>
              </li>
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Clock className="w-3.5 h-3.5 text-purple-400" /> Session Limit
                </span>
                <span className="font-bold text-white">
                  {entitlement?.max_session_minutes
                    ? `${entitlement.max_session_minutes / 60}h`
                    : "4h"}
                </span>
              </li>
              <li className="flex items-center justify-between border-b border-white/5 pb-2">
                <span className="flex items-center gap-2">
                  <Video className="w-3.5 h-3.5 text-purple-400" /> Facecams
                </span>
                <span className="font-bold text-white uppercase">
                  {entitlement?.av_level ?? "voice"}
                </span>
              </li>
            </ul>
          </div>

          <div className="pt-2">
            <button
              onClick={handleExportData}
              className="text-[11px] text-gray-400 hover:text-purple-300 flex items-center gap-1.5 transition-colors cursor-pointer"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Export My Data (GDPR JSON)</span>
            </button>
          </div>
        </GlassPanel>
      </div>
    </div>
  );
}

export default function AccountPage() {
  return (
    <Suspense
      fallback={
        <div className="max-w-4xl mx-auto py-24 text-center text-sm text-gray-400">
          Loading dashboard...
        </div>
      }
    >
      <AccountDashboard />
    </Suspense>
  );
}
