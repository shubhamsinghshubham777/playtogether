"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Logo } from "@/components/Logo";
import { GlassPanel } from "@/components/GlassPanel";
import { PTButton } from "@/components/PTButton";
import { CheckCircle2, AlertCircle, ExternalLink, ArrowRight, ShieldCheck } from "lucide-react";

function DesktopCallbackContent() {
  const searchParams = useSearchParams();
  const [deepLinkUrl, setDeepLinkUrl] = useState<string>("synctogether://auth-callback");
  const [isError, setIsError] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [redirectAttempted, setRedirectAttempted] = useState(false);

  useEffect(() => {
    // Construct the complete deep link with all query parameters and hash fragments
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
    }

    // Automatically trigger the deep link to focus and authenticate the desktop app
    const timer = setTimeout(() => {
      try {
        window.location.href = targetUri;
      } catch (err) {
        console.error("Deep link navigation error:", err);
      } finally {
        setRedirectAttempted(true);
      }
    }, 150);

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
        className="p-8 sm:p-10 space-y-6 max-w-md w-full border-rose-500/25 bg-[#141024]/90 text-center"
      >
        <div className="flex justify-center mb-2">
          <Logo size="lg" />
        </div>

        <div className="mx-auto w-16 h-16 rounded-full bg-rose-500/10 border border-rose-500/30 flex items-center justify-center text-rose-400 shadow-lg shadow-rose-500/10 animate-in fade-in zoom-in duration-300">
          <AlertCircle className="w-8 h-8" />
        </div>

        <div className="space-y-2">
          <h1 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            Authentication Incomplete
          </h1>
          <p className="text-sm text-gray-400 leading-relaxed">
            {errorMessage || "We were unable to complete your sign-in request."}
          </p>
        </div>

        <div className="pt-2 flex flex-col gap-3">
          <PTButton
            variant="primary"
            size="lg"
            className="w-full justify-center"
            onClick={handleManualOpen}
          >
            <span>Return to SyncTogether</span>
            <ArrowRight className="w-4 h-4" />
          </PTButton>

          <a
            href="/auth"
            className="text-xs text-purple-300 hover:text-purple-200 transition-colors underline underline-offset-4"
          >
            Try signing in again
          </a>
        </div>
      </GlassPanel>
    );
  }

  return (
    <GlassPanel
      glow="purple"
      className="p-8 sm:p-10 space-y-6 max-w-md w-full border-purple-500/25 bg-[#141024]/90 text-center relative"
    >
      <div className="flex justify-center mb-2">
        <Logo size="lg" />
      </div>

      {/* Success Animated Badge */}
      <div className="relative mx-auto w-20 h-20 flex items-center justify-center">
        <div className="absolute inset-0 rounded-full bg-emerald-500/20 blur-xl animate-pulse" />
        <div className="relative w-16 h-16 rounded-full bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-center text-emerald-400 shadow-lg shadow-emerald-500/20">
          <CheckCircle2 className="w-9 h-9 animate-in zoom-in duration-300" />
        </div>
      </div>

      <div className="space-y-2">
        <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs font-medium tracking-wide">
          <ShieldCheck className="w-3.5 h-3.5" />
          <span>Signed In Successfully</span>
        </div>

        <h1 className="text-2xl sm:text-3xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
          Login Successful!
        </h1>
        <p className="text-sm text-gray-300 leading-relaxed">
          You&apos;ve successfully authenticated with Google. You can return to the SyncTogether desktop app now.
        </p>
      </div>

      {/* Primary Action Button */}
      <div className="space-y-3 pt-2">
        <PTButton
          variant="primary"
          size="lg"
          className="w-full justify-center shadow-lg shadow-purple-900/40 group"
          onClick={handleManualOpen}
        >
          <span>Open SyncTogether App</span>
          <ExternalLink className="w-4 h-4 transition-transform duration-200 group-hover:scale-110" />
        </PTButton>

        <p className="text-xs text-gray-400 leading-relaxed">
          {redirectAttempted
            ? "If SyncTogether didn't open automatically, click the button above. You can safely close this browser window."
            : "Redirecting you back to the desktop application..."}
        </p>
      </div>
    </GlassPanel>
  );
}

export default function DesktopCallbackPage() {
  return (
    <div className="min-h-[80vh] flex items-center justify-center px-4 py-12 relative overflow-hidden">
      {/* Background Ambient Glow */}
      <div className="glow-blob-purple top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 opacity-30 pointer-events-none" />

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
