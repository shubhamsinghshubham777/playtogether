import Link from "next/link";
import { PTButton } from "@/components/PTButton";
import { GlassPanel } from "@/components/GlassPanel";
import { HeroSyncSimulator } from "@/components/HeroSyncSimulator";
import { TierPreviewSection } from "@/components/TierPreviewSection";
import { getLatestRelease } from "@/lib/github";
import {
  Download,
  Film,
  MessageCircle,
  Video,
  Clock,
  UserCheck,
  ShieldCheck,
  ArrowRight,
  Sparkles,
} from "lucide-react";

export default async function HomePage() {
  const release = await getLatestRelease();
  const displayTag = release.name || `v${release.version || "0.11.0"}`;

  return (
    <div className="relative overflow-hidden">
      {/* Background Ambient Glows */}
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-40" />
      <div className="glow-blob-cyan top-96 -left-40 opacity-25" />

      {/* 1. HERO SECTION */}
      <section className="relative pt-12 pb-20 md:pt-20 md:pb-28 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto text-center space-y-8">
        {/* Release / Intro Pill */}
        <Link
          href="/changelog"
          className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-purple-500/10 border border-purple-400/30 text-purple-200 text-xs font-semibold shadow-inner hover:bg-purple-500/20 hover:border-purple-400/50 hover:text-white transition-all duration-200 group cursor-pointer"
        >
          <Sparkles className="w-3.5 h-3.5 text-amber-300 animate-pulse group-hover:scale-110 transition-transform" />
          <span>SyncTogether {displayTag} is now live</span>
          <ArrowRight className="w-3 h-3 text-purple-400 group-hover:translate-x-0.5 transition-transform" />
        </Link>

        {/* Hero Title */}
        <div className="space-y-4 max-w-4xl mx-auto">
          <h1 className="text-4xl sm:text-6xl lg:text-7xl font-extrabold tracking-tight font-[family-name:var(--font-space-grotesk)] leading-[1.1]">
            Watch movies &amp; videos together in{" "}
            <span className="text-gradient-brand">millisecond sync.</span>
          </h1>
          <p className="text-lg sm:text-xl text-gray-300 max-w-2xl mx-auto leading-relaxed font-[family-name:var(--font-outfit)]">
            Synchronize your local media files or YouTube streams with friends.
            Featuring ultra-low latency voice &amp; video facecams, real-time chat,
            and persistent room memory.
          </p>
        </div>

        {/* Dual Download CTAs */}
        <div className="flex flex-col sm:flex-row items-center justify-center gap-4 pt-2">
          <PTButton
            href="/download"
            variant="primary"
            size="lg"
            leftIcon={<Download className="w-5 h-5" />}
          >
            Download for macOS
          </PTButton>
          <PTButton
            href="/download"
            variant="secondary"
            size="lg"
            leftIcon={<Download className="w-5 h-5" />}
          >
            Download for Windows
          </PTButton>
        </div>
        <p className="text-xs text-gray-400 font-mono">
          Free to use • No account required for guests • Direct standalone installer
        </p>

        {/* Interactive Simulated Experience */}
        <div className="pt-8 md:pt-12">
          <HeroSyncSimulator />
        </div>
      </section>

      {/* 2. HOW IT WORKS */}
      <section className="relative py-20 bg-[#090812] border-y border-purple-500/10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center max-w-2xl mx-auto mb-16 space-y-3">
            <h2 className="text-xs font-bold uppercase tracking-widest text-purple-400 font-mono">
              Simple 3-Step Setup
            </h2>
            <p className="text-3xl sm:text-4xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
              From zero to watching in under 10 seconds.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {/* Step 1 */}
            <GlassPanel hoverEffect className="space-y-4">
              <div className="w-12 h-12 rounded-xl bg-purple-600/20 border border-purple-500/30 flex items-center justify-center text-purple-300 font-bold font-mono text-lg">
                01
              </div>
              <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Create a Room
              </h3>
              <p className="text-sm text-gray-400 leading-relaxed">
                Launch the app and generate a private room in one click. Pick any
                local video file on your computer or paste a YouTube URL.
              </p>
            </GlassPanel>

            {/* Step 2 */}
            <GlassPanel hoverEffect className="space-y-4">
              <div className="w-12 h-12 rounded-xl bg-purple-600/20 border border-purple-500/30 flex items-center justify-center text-purple-300 font-bold font-mono text-lg">
                02
              </div>
              <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Share Room Code
              </h3>
              <p className="text-sm text-gray-400 leading-relaxed">
                Send your unique 6-character room code or one-click{" "}
                <code className="text-xs text-purple-300 bg-purple-950/80 px-1 py-0.5 rounded">
                  synctogether://
                </code>{" "}
                invite link to your friends.
              </p>
            </GlassPanel>

            {/* Step 3 */}
            <GlassPanel hoverEffect className="space-y-4">
              <div className="w-12 h-12 rounded-xl bg-purple-600/20 border border-purple-500/30 flex items-center justify-center text-purple-300 font-bold font-mono text-lg">
                03
              </div>
              <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                Watch in Sync
              </h3>
              <p className="text-sm text-gray-400 leading-relaxed">
                Play, pause, seek, and scrub in perfect sync. Talk over
                low-latency voice or video, react with animated emoji, and chat.
              </p>
            </GlassPanel>
          </div>
        </div>
      </section>

      {/* 3. CORE FEATURES */}
      <section id="features" className="relative py-24 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto">
        <div className="text-center max-w-3xl mx-auto mb-16 space-y-3">
          <h2 className="text-xs font-bold uppercase tracking-widest text-purple-400 font-mono">
            Engineered for Media Enthusiasts
          </h2>
          <p className="text-3xl sm:text-5xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
            Everything you need for the ultimate watch party.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
          {/* Feature 1 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-purple-500/10 text-purple-300 w-fit border border-purple-500/20">
              <Film className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Sync Any Media
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              Native hardware-accelerated playback for local MKV,
              MP4, and 4K HDR files alongside direct YouTube stream sync.
            </p>
          </GlassPanel>

          {/* Feature 2 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-pink-500/10 text-pink-300 w-fit border border-pink-500/20">
              <Video className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Voice &amp; Video Facecams
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              Ultra-low latency real-time facecams. See and hear your friends with
              crisp 1080p video, active speaker detection, and low CPU overhead.
            </p>
          </GlassPanel>

          {/* Feature 3 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-cyan-500/10 text-cyan-300 w-fit border border-cyan-500/20">
              <MessageCircle className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Chat &amp; Animated Reactions
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              Session-scoped chat with typing indicators and 24 Google Noto Lottie
              animated emoji that pop over the video in real-time.
            </p>
          </GlassPanel>

          {/* Feature 4 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-amber-500/10 text-amber-300 w-fit border border-amber-500/20">
              <Clock className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Rooms That Nap
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              Need a break? Your room saves its media timestamp and reopens
              seamlessly. Free rooms nap for 24h; Premium rooms persist forever.
            </p>
          </GlassPanel>

          {/* Feature 5 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-emerald-500/10 text-emerald-300 w-fit border border-emerald-500/20">
              <UserCheck className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              Zero Friction Guest Access
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              Your friends don&apos;t need to register or sign in to join your
              watch party. One click enters them into the room instantly.
            </p>
          </GlassPanel>

          {/* Feature 6 */}
          <GlassPanel hoverEffect className="space-y-3">
            <div className="p-3 rounded-xl bg-indigo-500/10 text-indigo-300 w-fit border border-indigo-500/20">
              <ShieldCheck className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
              100% Private &amp; Direct
            </h3>
            <p className="text-sm text-gray-400 leading-relaxed">
              Your files never upload to our servers. File names, directory
              paths, and video buffers remain strictly on your local machine.
            </p>
          </GlassPanel>
        </div>
      </section>

      {/* 4. TIER PREVIEW SECTION */}
      <TierPreviewSection />

      {/* 5. BOTTOM DOWNLOAD CTA */}
      <section className="relative py-24 px-4 sm:px-6 lg:px-8 max-w-5xl mx-auto text-center">
        <GlassPanel glow="purple" className="py-16 px-8 sm:px-12 space-y-8 border-purple-400/30">
          <div className="space-y-3 max-w-2xl mx-auto">
            <h2 className="text-3xl sm:text-5xl font-extrabold text-white font-[family-name:var(--font-space-grotesk)]">
              Ready to watch together?
            </h2>
            <p className="text-base text-gray-300">
              Download SyncTogether for free and host your first watch party in seconds.
            </p>
          </div>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <PTButton
              href="/download"
              variant="primary"
              size="lg"
              leftIcon={<Download className="w-5 h-5" />}
            >
              Download for macOS
            </PTButton>
            <PTButton
              href="/download"
              variant="secondary"
              size="lg"
              leftIcon={<Download className="w-5 h-5" />}
            >
              Download for Windows
            </PTButton>
          </div>
        </GlassPanel>
      </section>
    </div>
  );
}
