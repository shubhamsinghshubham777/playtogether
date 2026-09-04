import type { Metadata } from "next";
import { GlassPanel } from "@/components/GlassPanel";
import { PTButton } from "@/components/PTButton";
import { getLatestRelease } from "@/lib/github";
import {
  Download,
  Smartphone,
  Sparkles,
} from "lucide-react";

function AppleLogo({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
    </svg>
  );
}

function WindowsLogo({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M0 0h11v11H0zM13 0h11v11H13zM0 13h11v11H0zM13 13h11v11H13z" />
    </svg>
  );
}

export const metadata: Metadata = {
  title: "Download SyncTogether for macOS and Windows",
  description:
    "Download the latest version of SyncTogether standalone desktop app for macOS (Apple Silicon & Intel) and Windows 10/11.",
};

export default async function DownloadPage() {
  const release = await getLatestRelease();

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto space-y-16">
      {/* Background Ambient Glow */}
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-30" />

      {/* Header */}
      <div className="text-center max-w-3xl mx-auto space-y-4">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-purple-500/10 border border-purple-400/20 text-xs font-mono text-purple-300">
          <Sparkles className="w-3.5 h-3.5 text-amber-300" />
          <span>Latest Release: {release.name || `v${release.version}`}</span>
        </div>
        <h1 className="text-4xl sm:text-6xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Download <span className="text-gradient-brand">SyncTogether.</span>
        </h1>
        <p className="text-lg text-gray-300">
          Standalone desktop application with native hardware acceleration, zero bloat, and automatic self-updates.
        </p>
      </div>

      {/* Platform Download Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto">
        {/* macOS Card */}
        <GlassPanel
          hoverEffect
          glow="purple"
          className="flex flex-col justify-between p-8 space-y-6 border-purple-500/20"
        >
          <div className="space-y-4">
            <div className="w-14 h-14 rounded-2xl bg-purple-500/10 border border-purple-400/30 flex items-center justify-center text-purple-300 shadow-inner">
              <AppleLogo className="w-7 h-7" />
            </div>
            <div>
              <h2 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                macOS
              </h2>
              <p className="text-xs text-gray-400 mt-0.5">
                Universal Binary • Apple Silicon &amp; Intel
              </p>
            </div>
            <div className="text-xs font-mono text-purple-300/80 bg-purple-950/40 p-2.5 rounded-xl border border-purple-500/15">
              <span>Version: <strong>{release.version}</strong></span> • <span>Size: ~{release.macSizeMb} MB</span>
            </div>
          </div>

          <div className="space-y-3 pt-4 border-t border-white/5">
            <PTButton
              href={release.macDownloadUrl}
              variant="primary"
              size="lg"
              className="w-full"
              leftIcon={<Download className="w-5 h-5" />}
            >
              Download macOS (.dmg)
            </PTButton>
            <p className="text-[11px] text-center text-gray-400">
              Requires macOS 12.0 (Monterey) or later
            </p>
          </div>
        </GlassPanel>

        {/* Windows Card */}
        <GlassPanel
          hoverEffect
          glow="purple"
          className="flex flex-col justify-between p-8 space-y-6 border-purple-500/20"
        >
          <div className="space-y-4">
            <div className="w-14 h-14 rounded-2xl bg-purple-500/10 border border-purple-400/30 flex items-center justify-center text-purple-300 shadow-inner">
              <WindowsLogo className="w-7 h-7" />
            </div>
            <div>
              <h2 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Windows
              </h2>
              <p className="text-xs text-gray-400 mt-0.5">
                64-bit Installer • Windows 10 &amp; Windows 11
              </p>
            </div>
            <div className="text-xs font-mono text-purple-300/80 bg-purple-950/40 p-2.5 rounded-xl border border-purple-500/15">
              <span>Version: <strong>{release.version}</strong></span> • <span>Size: ~{release.winSizeMb} MB</span>
            </div>
          </div>

          <div className="space-y-3 pt-4 border-t border-white/5">
            <PTButton
              href={release.winDownloadUrl}
              variant="secondary"
              size="lg"
              className="w-full"
              leftIcon={<Download className="w-5 h-5" />}
            >
              Download Windows (.exe)
            </PTButton>
            <p className="text-[11px] text-center text-gray-400">
              Windows 10 / 11 with WebView2 runtime
            </p>
          </div>
        </GlassPanel>
      </div>

      {/* Mobile Teaser Card */}
      <div className="max-w-4xl mx-auto">
        <GlassPanel className="p-6 flex flex-col sm:flex-row items-center justify-between gap-6 border-white/5 bg-[#120E22]/60">
          <div className="flex items-center gap-4">
            <div className="p-3 rounded-2xl bg-purple-500/10 text-purple-400 border border-purple-500/20">
              <Smartphone className="w-6 h-6" />
            </div>
            <div>
              <h4 className="text-base font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Mobile Apps Coming Soon
              </h4>
              <p className="text-xs text-gray-400">
                SyncTogether is built desktop-first for big screens. iOS and Android companion apps are currently on our roadmap.
              </p>
            </div>
          </div>
          <span className="text-xs font-mono font-bold px-3 py-1.5 rounded-full bg-purple-500/10 text-purple-300 border border-purple-400/20 whitespace-nowrap">
            In Development
          </span>
        </GlassPanel>
      </div>
    </div>
  );
}
