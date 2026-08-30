"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { GlassPanel } from "@/components/GlassPanel";
import { PTButton } from "@/components/PTButton";
import confetti from "canvas-confetti";
import {
  Check,
  AlertCircle,
  ArrowUpRight,
  ArrowRight,
  Sparkles,
  Layers,
} from "lucide-react";

function DesktopCallbackContent() {
  const searchParams = useSearchParams();
  const [deepLinkUrl, setDeepLinkUrl] = useState<string>("synctogether://auth-callback");
  const [isError, setIsError] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    // Extract query and hash fragments
    const search = window.location.search || "";
    const hash = window.location.hash || "";
    const targetUri = `synctogether://auth-callback${search}${hash}`;
    setDeepLinkUrl(targetUri);

    // Check for error parameters
    const error = searchParams.get("error") || searchParams.get("error_code");
    const errorDesc =
      searchParams.get("error_description") ||
      searchParams.get("error_message") ||
      (error ? "The authentication process was cancelled or failed." : null);

    if (error || errorDesc) {
      setIsError(true);
      setErrorMessage(
        errorDesc?.replace(/\+/g, " ") || "Authentication could not be completed."
      );
      return;
    }

    // Gentle celebratory confetti
    try {
      confetti({
        particleCount: 45,
        spread: 60,
        origin: { y: 0.65 },
        colors: ["#8B5CF6", "#A855F7", "#4ADE80", "#C9B8FF"],
        disableForReducedMotion: true,
      });
    } catch {
      // Ignore if confetti fails in headless/SSR environments
    }

    // Automatically trigger deep-link launch
    const timer = setTimeout(() => {
      try {
        window.location.href = targetUri;
      } catch (err) {
        console.error("Deep link navigation error:", err);
      }
    }, 250);

    return () => clearTimeout(timer);
  }, [searchParams]);

  const handleManualOpen = () => {
    if (deepLinkUrl) {
      window.location.href = deepLinkUrl;
    }
  };

  if (isError) {
    return (
      <GlassPanel
        glow="purple"
        className="p-8 sm:p-10 space-y-6 max-w-md w-full border-rose-500/25 bg-[#120F20]/90 text-center relative shadow-2xl"
      >
        {/* Error Icon */}
        <div className="mx-auto w-16 h-16 rounded-2xl bg-rose-500/10 border border-rose-500/30 flex items-center justify-center text-rose-400 shadow-lg shadow-rose-500/10">
          <AlertCircle className="w-8 h-8" />
        </div>

        <div className="space-y-2">
          <h1 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            Sign-in Incomplete
          </h1>
          <p className="text-xs text-gray-400 leading-relaxed max-w-xs mx-auto">
            {errorMessage || "We couldn't finish signing you in. Please try again."}
          </p>
        </div>

        <div className="pt-2 flex flex-col gap-2.5">
          <PTButton
            variant="primary"
            size="md"
            className="w-full justify-center"
            onClick={handleManualOpen}
            rightIcon={<ArrowRight className="w-4 h-4" />}
          >
            Return to App
          </PTButton>

          <Link
            href="/auth"
            className="text-xs text-purple-300/80 hover:text-purple-200 transition-colors py-1.5"
          >
            Try signing in again
          </Link>
        </div>
      </GlassPanel>
    );
  }

  return (
    <GlassPanel
      glow="purple"
      className="p-8 sm:p-10 max-w-md w-full border-white/10 bg-[#120F20]/95 text-center relative shadow-2xl space-y-6"
    >
      {/* Unified Hero: Brand Icon with Integrated Success Badge */}
      <div className="relative mx-auto w-20 h-20 flex items-center justify-center">
        {/* Ambient Halo */}
        <div className="absolute inset-0 rounded-2xl bg-purple-500/20 blur-xl animate-pulse pointer-events-none" />

        {/* SyncTogether Icon */}
        <div className="w-16 h-16 rounded-2xl btn-primary-gradient p-0.5 shadow-xl shadow-purple-950/60 flex items-center justify-center">
          <div className="w-full h-full bg-[#141026] rounded-[14px] flex items-center justify-center">
            <svg
              className="w-7 h-7 text-[#C9B8FF] fill-current ml-0.5"
              viewBox="0 0 24 24"
            >
              <path d="M8 5.14v14l11-7-11-7z" />
            </svg>
          </div>
        </div>

        {/* Integrated Checkmark Badge */}
        <div className="absolute -bottom-1 -right-1 w-7 h-7 rounded-full bg-emerald-500 text-black flex items-center justify-center shadow-lg shadow-emerald-500/40 border-2 border-[#120F20] animate-in zoom-in-50 duration-300">
          <Check className="w-4 h-4 stroke-[3]" />
        </div>
      </div>

      {/* Typography */}
      <div className="space-y-2">
        <h1 className="text-2xl sm:text-3xl font-bold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          You&apos;re All Set!
        </h1>
        <p className="text-xs sm:text-sm text-gray-300/90 leading-relaxed max-w-xs mx-auto">
          Successfully signed in with Google. We&apos;ve sent your session to the SyncTogether desktop app.
        </p>
      </div>

      {/* Action Area */}
      <div className="space-y-3 pt-1">
        <PTButton
          variant="primary"
          size="lg"
          className="w-full justify-center shadow-xl shadow-purple-950/50"
          onClick={handleManualOpen}
          rightIcon={<ArrowUpRight className="w-4 h-4" />}
        >
          Open SyncTogether
        </PTButton>

        <p className="text-xs text-gray-400 leading-relaxed">
          If SyncTogether didn&apos;t open automatically, click the button above. You can safely close this browser tab.
        </p>
      </div>

      {/* Helpful Subtle Footer Links */}
      <div className="pt-4 border-t border-white/[0.06] flex items-center justify-between text-[11px] text-gray-500 px-1">
        <span className="flex items-center gap-1">
          <Sparkles className="w-3 h-3 text-purple-400/80" />
          <span>Sync & Watch in 4K</span>
        </span>
        <Link
          href="/account"
          className="text-purple-400/80 hover:text-purple-300 transition-colors inline-flex items-center gap-1"
        >
          <Layers className="w-3 h-3" />
          <span>Web Dashboard</span>
        </Link>
      </div>
    </GlassPanel>
  );
}

export default function DesktopCallbackPage() {
  return (
    <div className="min-h-[80vh] flex items-center justify-center px-4 py-12 relative overflow-hidden">
      {/* Subtle Background Glows */}
      <div className="glow-blob-purple top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 opacity-25 pointer-events-none" />
      <div className="glow-blob-gold top-1/3 right-1/4 opacity-10 pointer-events-none" />

      <Suspense
        fallback={
          <GlassPanel className="p-8 max-w-md w-full text-center text-sm text-gray-400">
            Completing authentication...
          </GlassPanel>
        }
      >
        <DesktopCallbackContent />
      </Suspense>
    </div>
  );
}
