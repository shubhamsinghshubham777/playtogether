"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Logo } from "@/components/Logo";
import { GlassPanel } from "@/components/GlassPanel";
import { createClient } from "@/lib/supabase/client";
import { ShieldCheck, Info } from "lucide-react";

function AuthCard() {
  const searchParams = useSearchParams();
  const redirect = searchParams.get("redirect") || "/account";
  const [isLoading, setIsLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const supabase = createClient();

  const handleGoogleSignIn = async () => {
    setIsLoading(true);
    setErrorMsg(null);
    try {
      const redirectTo = `${window.location.origin}/auth/callback?redirect=${encodeURIComponent(
        redirect
      )}`;

      const { error } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          redirectTo,
          queryParams: {
            access_type: "offline",
            prompt: "consent",
          },
        },
      });

      if (error) {
        throw error;
      }
    } catch (err: unknown) {
      console.error("Google sign in error:", err);
      setErrorMsg(
        err instanceof Error ? err.message : "Failed to initiate sign in"
      );
      setIsLoading(false);
    }
  };

  return (
    <GlassPanel
      glow="purple"
      className="p-8 sm:p-10 space-y-6 max-w-md w-full border-purple-500/25 bg-[#141024]/90"
    >
      <div className="text-center space-y-3">
        <div className="flex justify-center mb-2">
          <Logo size="lg" />
        </div>
        <h1 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
          Welcome to PlayTogether
        </h1>
        <p className="text-xs text-gray-400 leading-relaxed">
          Sign in with your Google account to manage your subscription, unlock 4-hour rooms, and sync across all your devices.
        </p>
      </div>

      {errorMsg && (
        <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-300 text-xs">
          {errorMsg}
        </div>
      )}

      {/* Google Sign-in Button */}
      <button
        onClick={handleGoogleSignIn}
        disabled={isLoading}
        className="w-full py-3 px-4 rounded-xl bg-white hover:bg-gray-100 text-gray-900 font-semibold text-sm flex items-center justify-center gap-3 transition-all duration-200 shadow-lg shadow-white/5 active:scale-[0.98] cursor-pointer disabled:opacity-50"
      >
        <svg className="w-5 h-5" viewBox="0 0 24 24">
          <path
            fill="#4285F4"
            d="M23.745 12.27c0-.7-.06-1.4-.19-2.07H12v4.51h6.6c-.29 1.52-1.14 2.82-2.4 3.68v3.05h3.88c2.27-2.09 3.665-5.17 3.665-9.17z"
          />
          <path
            fill="#34A853"
            d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.88-3.05c-1.08.72-2.45 1.16-4.05 1.16-3.12 0-5.77-2.1-6.72-4.93H1.25v3.15C3.26 21.36 7.33 24 12 24z"
          />
          <path
            fill="#FBBC05"
            d="M5.28 14.27c-.25-.72-.38-1.49-.38-2.27s.13-1.55.38-2.27V6.58H1.25C.45 8.18 0 10.02 0 12s.45 3.82 1.25 5.42l4.03-3.15z"
          />
          <path
            fill="#EA4335"
            d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.33 0 3.26 2.64 1.25 6.58l4.03 3.15c.95-2.83 3.6-4.98 6.72-4.98z"
          />
        </svg>
        <span>{isLoading ? "Connecting to Google..." : "Continue with Google"}</span>
      </button>

      {/* Info Notice */}
      <div className="p-3.5 rounded-xl bg-purple-500/10 border border-purple-400/20 text-[11px] text-purple-200/90 leading-relaxed flex items-start gap-2.5">
        <Info className="w-4 h-4 text-purple-300 shrink-0 mt-0.5" />
        <span>
          We use Google identity to guarantee seamless cross-device authentication between your browser and the desktop app.
        </span>
      </div>

      <div className="pt-2 border-t border-white/5 text-center">
        <p className="text-[11px] text-gray-500 flex items-center justify-center gap-1.5">
          <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
          <span>Secure authentication via Supabase Auth</span>
        </p>
      </div>
    </GlassPanel>
  );
}

export default function AuthPage() {
  return (
    <div className="min-h-[80vh] flex items-center justify-center px-4 py-12 relative overflow-hidden">
      {/* Background Ambient Glow */}
      <div className="glow-blob-purple top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 opacity-30" />

      <Suspense
        fallback={
          <GlassPanel className="p-8 max-w-md w-full text-center text-sm text-gray-400">
            Loading authentication...
          </GlassPanel>
        }
      >
        <AuthCard />
      </Suspense>
    </div>
  );
}
