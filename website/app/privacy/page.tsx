import type { Metadata } from "next";
import { GlassPanel } from "@/components/GlassPanel";
import { SITE_CONFIG } from "@/lib/constants";
import {
  ShieldCheck,
  Lock,
  EyeOff,
  Trash2,
  Download,
  Server,
  Video,
  Mic,
  FileVideo,
  Play,
  Globe,
  Database,
  ExternalLink,
  Cpu,
  RefreshCw,
  Scale,
  UserCheck,
} from "lucide-react";

export const metadata: Metadata = {
  title: "Privacy Policy — Complete Data Protection & Security",
  description:
    "Learn how SyncTogether protects your personal data, media privacy, real-time voice and video streams, and payment information.",
};

export default function PrivacyPage() {
  const lastUpdated = "August 30, 2026";
  const effectiveDate = "August 30, 2026";

  const subprocessors = [
    {
      name: "Supabase, Inc.",
      purpose: "Authentication, user profiles, PostgreSQL cloud database with Row Level Security, private real-time synchronization channels, and serverless Edge Functions.",
      location: "United States / Global AWS",
      privacyUrl: "https://supabase.com/privacy",
    },
    {
      name: "Cloudflare, Inc.",
      purpose: "Cloudflare Turnstile bot detection for guest signups, Cloudflare R2 Object Storage for temporary Cloud Media Sharing, DNS, and DDoS protection.",
      location: "United States / Global Edge",
      privacyUrl: "https://www.cloudflare.com/privacypolicy/",
    },
    {
      name: "LiveKit, Inc. (LiveKit Cloud)",
      purpose: "Encrypted WebRTC real-time Selective Forwarding Unit (SFU) media relay for voice chat and video facecams.",
      location: "United States / Global Relays",
      privacyUrl: "https://livekit.com/legal/privacy-policy",
    },
    {
      name: "Paddle Payments Ltd / Paddle.com",
      purpose: "Authorized Merchant of Record (MoR) handling payment processing, billing subscriptions, invoices, and sales tax / VAT compliance.",
      location: "United Kingdom / United States",
      privacyUrl: "https://www.paddle.com/legal/privacy",
    },
    {
      name: "Functional Software, Inc. (Sentry)",
      purpose: "Application stability monitoring, crash reporting, and diagnostics telemetry (error stack traces and OS versions).",
      location: "United States",
      privacyUrl: "https://sentry.io/privacy/",
    },
    {
      name: "PostHog, Inc.",
      purpose: "Privacy-conscious product analytics and feature engagement tracking (with full client-side opt-out support).",
      location: "United States / European Union",
      privacyUrl: "https://posthog.com/privacy",
    },
    {
      name: "Vercel, Inc.",
      purpose: "Marketing website and account portal hosting, edge middleware routing, and privacy-friendly web traffic analytics.",
      location: "United States / Global Edge",
      privacyUrl: "https://vercel.com/legal/privacy-policy",
    },
    {
      name: "Google LLC",
      purpose: "Google OAuth 2.0 single sign-on authentication and YouTube IFrame video player embeds.",
      location: "United States / Global",
      privacyUrl: "https://policies.google.com/privacy",
    },
  ];

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-12">
      {/* Header */}
      <div className="space-y-3 text-center sm:text-left">
        <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-purple-500/10 border border-purple-500/20 text-xs sm:text-sm font-mono text-purple-400 font-bold uppercase tracking-wider">
          <ShieldCheck className="w-4 h-4" />
          <span>Privacy &amp; Data Protection</span>
        </div>
        <h1 className="text-4xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Privacy Policy
        </h1>
        <div className="flex flex-wrap items-center gap-4 text-xs sm:text-sm text-gray-400 font-mono">
          <span>Effective: {effectiveDate}</span>
          <span>&bull;</span>
          <span>Last Updated: {lastUpdated}</span>
        </div>
      </div>

      <GlassPanel className="p-8 sm:p-12 space-y-12 text-sm sm:text-base text-gray-300 leading-relaxed border-purple-500/20">
        {/* Core Privacy Pledge */}
        <section className="space-y-3">
          <div className="p-6 rounded-2xl bg-gradient-to-br from-purple-950/40 via-purple-900/20 to-transparent border border-purple-500/30 space-y-3 text-purple-200 text-sm sm:text-base leading-relaxed">
            <div className="flex items-center gap-2.5 font-bold text-white text-lg">
              <ShieldCheck className="w-5 h-5 text-emerald-400 shrink-0" />
              <span>Our Privacy Pledge</span>
            </div>
            <p>
              SyncTogether is designed around privacy by architecture. When synchronizing local files, your video bytes and absolute disk paths never leave your device. When using real-time facecams and voice chat, streams are end-to-end encrypted in transit and <strong>never recorded or stored</strong> on any server. We do not sell your personal data, and we do not track you across the web.
            </p>
          </div>
        </section>

        {/* 1. Scope & Applicability */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <Globe className="w-5 h-5 text-purple-400 shrink-0" />
            <span>1. Scope &amp; Services Covered</span>
          </h2>
          <p className="text-gray-300">
            This Privacy Policy governs your use of the <strong>SyncTogether</strong> platform, including:
          </p>
          <ul className="space-y-2 text-gray-400 list-disc list-inside">
            <li>
              The SyncTogether desktop client applications (macOS, Windows, and Linux).
            </li>
            <li>
              The official website, documentation, and subscription management portal located at{" "}
              <a href="https://synctogether.app" className="text-purple-300 underline hover:text-white">
                https://synctogether.app
              </a>.
            </li>
            <li>
              Our cloud infrastructure, authentication bridges, real-time synchronization channels, media sharing services, and serverless edge functions.
            </li>
          </ul>
        </section>

        {/* 2. Information We Collect */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <Database className="w-5 h-5 text-purple-400 shrink-0" />
            <span>2. Information We Collect &amp; How We Process It</span>
          </h2>
          <div className="space-y-4 text-gray-300">
            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">A. Account &amp; Identity Data</strong>
              <ul className="space-y-1.5 text-gray-400 list-disc list-inside">
                <li>
                  <strong className="text-gray-200">Google OAuth Sign-In:</strong> When you sign in using Google OAuth, we receive and store your email address, full display name, and avatar image URL provided by Google.
                </li>
                <li>
                  <strong className="text-gray-200">Guest Authentication:</strong> If you use SyncTogether as a Guest without an account, we generate a temporary random anonymous identifier (e.g. <code>Guest-a1b2</code>). Guest sessions use Cloudflare Turnstile tokens to verify human interaction and prevent automated abuse.
                </li>
                <li>
                  <strong className="text-gray-200">User Profiles:</strong> You may customize your public display name at any time in your profile settings.
                </li>
              </ul>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">B. Media Playback &amp; Synchronization Metadata</strong>
              <ul className="space-y-1.5 text-gray-400 list-disc list-inside">
                <li>
                  <strong className="text-gray-200">Local File Sync Mode:</strong> When syncing local video files, we process only the file&apos;s basic filename (basename, e.g. <code>movie.mp4</code>), duration, and playback timestamps (position, play, pause, seek) over private real-time channels. <em>Your absolute disk directory structure and raw video bytes remain on your local disk.</em>
                </li>
                <li>
                  <strong className="text-gray-200">Cloud Media Sharing Mode (Optional Host Upload):</strong> When a host chooses to stream a file directly to room participants via Cloud Media Sharing, the video file is encrypted in transit and uploaded temporarily to our Cloudflare R2 object storage. We store file size and chunk metadata to generate time-limited, presigned download URLs for authenticated room members.
                </li>
                <li>
                  <strong className="text-gray-200">YouTube Sync Mode:</strong> When synchronizing YouTube playback, we process the canonical YouTube Video ID, playback state, and timestamp coordinates.
                </li>
              </ul>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">C. Real-time Communication (Voice, Video &amp; Chat)</strong>
              <ul className="space-y-1.5 text-gray-400 list-disc list-inside">
                <li>
                  <strong className="text-gray-200">Voice &amp; Video Facecams:</strong> Live audio and video streams are transmitted in real-time over encrypted WebRTC connections via LiveKit Cloud. <strong>Voice and video streams are NEVER recorded, monitored, transcribed, or stored on our servers.</strong>
                </li>
                <li>
                  <strong className="text-gray-200">Room Chat &amp; Reactions:</strong> Text chat messages and emoji/Lottie reaction triggers are broadcast to room participants. In-room messages are temporary and tied strictly to the active room lifecycle.
                </li>
              </ul>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">D. Payment &amp; Subscription Information</strong>
              <p className="text-gray-400">
                Premium subscription payments are processed directly by our authorized Merchant of Record, <strong>Paddle Payments Ltd / Paddle.com</strong>. Paddle handles all credit card, debit card, PayPal, Apple Pay, Google Pay, and UPI transactions.
              </p>
              <p className="text-gray-400">
                <strong>SyncTogether never sees, processes, or stores your credit card numbers, CVVs, or bank account details.</strong> We receive only billing status confirmations, subscription tier flags, transaction IDs, and renewal timestamps from Paddle via verified webhooks.
              </p>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">E. Diagnostics, Crash Reports &amp; Analytics</strong>
              <ul className="space-y-1.5 text-gray-400 list-disc list-inside">
                <li>
                  <strong className="text-gray-200">Crash Reporting (Sentry):</strong> If an unexpected application failure occurs, Sentry captures stack traces, operating system version, app version, and breadcrumb execution context to assist our engineering team in resolving bugs.
                </li>
                <li>
                  <strong className="text-gray-200">Product Analytics (PostHog):</strong> We collect aggregated feature engagement metrics (e.g. room creation, sync latency, upgrade flows). <strong>You can opt out of analytics at any time</strong> with a single toggle in the desktop app under <em>Profile &rarr; &ldquo;Share usage data&rdquo;</em>. Opting out immediately stops all analytics event collection.
                </li>
                <li>
                  <strong className="text-gray-200">Web Analytics (Vercel Analytics):</strong> Our marketing website uses privacy-friendly Vercel Analytics to measure page view volume without tracking individual users or using invasive cookies.
                </li>
              </ul>
            </div>
          </div>
        </section>

        {/* 3. What We DO NOT Collect */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <EyeOff className="w-5 h-5 text-red-400 shrink-0" />
            <span>3. What We Explicitly DO NOT Collect or Do</span>
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm sm:text-base">
            <div className="p-4 sm:p-5 rounded-xl bg-red-500/5 border border-red-500/10 text-gray-300 space-y-1">
              <strong className="text-red-300 block mb-1 font-semibold">No Data Selling or Sharing</strong>
              We never sell, rent, monetize, or trade your personal data to advertisers, data brokers, or third parties.
            </div>
            <div className="p-4 sm:p-5 rounded-xl bg-red-500/5 border border-red-500/10 text-gray-300 space-y-1">
              <strong className="text-red-300 block mb-1 font-semibold">No Audio/Video Recordings</strong>
              We never record, listen to, store, or create transcripts of your live voice chat or video facecams.
            </div>
            <div className="p-4 sm:p-5 rounded-xl bg-red-500/5 border border-red-500/10 text-gray-300 space-y-1">
              <strong className="text-red-300 block mb-1 font-semibold">No Unselected File Scanning</strong>
              We never scan, index, read, or upload files, folders, or documents outside of the media file you deliberately select.
            </div>
            <div className="p-4 sm:p-5 rounded-xl bg-red-500/5 border border-red-500/10 text-gray-300 space-y-1">
              <strong className="text-red-300 block mb-1 font-semibold">No Cross-Site Tracking</strong>
              We do not use advertising tracking pixels, fingerprinting scripts, or cross-site behavioral trackers.
            </div>
          </div>
        </section>

        {/* 4. Media Architecture: Local vs Cloud vs YouTube */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <FileVideo className="w-5 h-5 text-purple-400 shrink-0" />
            <span>4. Media Playback Architecture &amp; YouTube Disclosures</span>
          </h2>
          <div className="space-y-3.5 text-gray-300">
            <p>
              SyncTogether offers flexible media options with distinct privacy boundaries:
            </p>
            <div className="space-y-3">
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">1. Local File Sync Mode (Peer Synchronization)</strong>
                <p className="text-gray-400">
                  When all room participants have their own copy of a video file on their device, SyncTogether coordinates playback strictly via lightweight control messages (play/pause/seek). <strong>Zero video bytes are transmitted to any server or other user.</strong>
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">2. Cloud Media Sharing Mode (Encrypted Cloudflare R2 Storage)</strong>
                <p className="text-gray-400">
                  When a host uploads a video file to stream to participants, the file is uploaded to an isolated, encrypted Cloudflare R2 storage bucket. Access is granted solely to authenticated room participants via time-limited, signed URLs. <strong>Shared media is strictly ephemeral and is automatically and permanently deleted upon room closure or expiration.</strong>
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2">
                <div className="flex items-center gap-2 font-semibold text-white text-base">
                  <Play className="w-4 h-4 text-red-500 fill-red-500 shrink-0" />
                  <span>3. YouTube API Services &amp; Embed Terms</span>
                </div>
                <p className="text-gray-400">
                  SyncTogether enables synchronized playback of public YouTube videos using the official YouTube IFrame API (via privacy-enhanced mode <code>youtube-nocookie.com</code>). By using YouTube playback in SyncTogether, you agree to be bound by the YouTube Terms of Service and acknowledge Google&apos;s Privacy Policy.
                </p>
                <div className="flex flex-wrap items-center gap-3 pt-1 text-purple-300 text-sm">
                  <a
                    href="https://www.youtube.com/t/terms"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 hover:text-white underline"
                  >
                    <span>YouTube Terms of Service</span>
                    <ExternalLink className="w-3.5 h-3.5" />
                  </a>
                  <span>&bull;</span>
                  <a
                    href="https://policies.google.com/privacy"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 hover:text-white underline"
                  >
                    <span>Google Privacy Policy</span>
                    <ExternalLink className="w-3.5 h-3.5" />
                  </a>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* 5. Device Permissions */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <Cpu className="w-5 h-5 text-purple-400 shrink-0" />
            <span>5. Hardware Permissions &amp; System Access</span>
          </h2>
          <p className="text-gray-300">
            The SyncTogether desktop app requests the following operating system permissions strictly on an as-needed basis:
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
              <div className="flex items-center gap-2 text-white font-semibold text-base">
                <Mic className="w-4 h-4 text-purple-400" />
                <span>Microphone Access</span>
              </div>
              <p className="text-gray-400">
                Used solely to transmit your audio when voice chat is explicitly unmuted by you in an active room.
              </p>
            </div>
            <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
              <div className="flex items-center gap-2 text-white font-semibold text-base">
                <Video className="w-4 h-4 text-purple-400" />
                <span>Camera Access</span>
              </div>
              <p className="text-gray-400">
                Used solely to capture and stream your video facecam when video is explicitly enabled by you in a room.
              </p>
            </div>
          </div>
        </section>

        {/* 6. Legal Bases for Processing (GDPR) */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <Scale className="w-5 h-5 text-purple-400 shrink-0" />
            <span>6. Legal Bases for Processing (GDPR / UK GDPR)</span>
          </h2>
          <div className="space-y-2 text-gray-400">
            <p className="text-gray-300">
              Under European data protection laws (GDPR / UK GDPR), we process personal data under the following lawful bases:
            </p>
            <ul className="space-y-2 list-disc list-inside">
              <li>
                <strong className="text-gray-200">Contractual Necessity (Art. 6(1)(b) GDPR):</strong> To authenticate your account, maintain room synchronization, manage subscriptions, and deliver the services you requested.
              </li>
              <li>
                <strong className="text-gray-200">Legitimate Interests (Art. 6(1)(f) GDPR):</strong> To detect bot abuse via Turnstile, troubleshoot software crashes via Sentry, and safeguard platform security.
              </li>
              <li>
                <strong className="text-gray-200">Consent (Art. 6(1)(a) GDPR):</strong> For optional product analytics via PostHog (which can be toggled off at any time).
              </li>
              <li>
                <strong className="text-gray-200">Legal Obligation (Art. 6(1)(c) GDPR):</strong> To comply with applicable tax, financial, and regulatory requirements via our Merchant of Record.
              </li>
            </ul>
          </div>
        </section>

        {/* 7. Subprocessors Table */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <Server className="w-5 h-5 text-purple-400 shrink-0" />
            <span>7. Authorized Third-Party Subprocessors</span>
          </h2>
          <p className="text-gray-300">
            We partner with industry-standard, privacy-compliant infrastructure providers to securely operate SyncTogether. All subprocessors are bound by data protection agreements:
          </p>
          <div className="overflow-x-auto rounded-xl border border-white/10 bg-white/[0.01]">
            <table className="w-full text-left text-xs sm:text-sm text-gray-300">
              <thead className="bg-white/5 text-white font-mono uppercase text-xs border-b border-white/10">
                <tr>
                  <th className="p-3.5">Subprocessor</th>
                  <th className="p-3.5">Purpose &amp; Service</th>
                  <th className="p-3.5">Location</th>
                  <th className="p-3.5">Privacy Link</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5 text-gray-400">
                {subprocessors.map((p) => (
                  <tr key={p.name} className="hover:bg-white/[0.02] transition-colors">
                    <td className="p-3.5 font-semibold text-white whitespace-nowrap">{p.name}</td>
                    <td className="p-3.5 leading-normal">{p.purpose}</td>
                    <td className="p-3.5 whitespace-nowrap">{p.location}</td>
                    <td className="p-3.5 whitespace-nowrap">
                      <a
                        href={p.privacyUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-purple-300 hover:text-white underline inline-flex items-center gap-1"
                      >
                        <span>Policy</span>
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* 8. Data Retention & Automatic Purge */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <RefreshCw className="w-5 h-5 text-purple-400 shrink-0" />
            <span>8. Data Retention &amp; Automatic Purge Schedules</span>
          </h2>
          <div className="space-y-3 text-gray-300">
            <p>
              We enforce strict automated data lifecycles to minimize data footprint:
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">Room Chat &amp; Reactions</strong>
                <p className="text-gray-400">
                  Cascade-deleted permanently from the database immediately when a room is ended by the host or reaches its expiration time.
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">Cloud Media Sharing (R2)</strong>
                <p className="text-gray-400">
                  Media files in R2 storage are purged automatically via database triggers and recurring automated sweeps whenever a room is closed or expires.
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">Guest Accounts</strong>
                <p className="text-gray-400">
                  Anonymous guest profiles inactive for more than 3 days without active rooms are purged daily via automated database routines.
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">Billing &amp; Tax Records</strong>
                <p className="text-gray-400">
                  Retained by Paddle Payments Ltd in accordance with statutory financial, tax, and accounting compliance requirements (typically 5–7 years).
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* 9. Cookies & Local Storage */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <Lock className="w-5 h-5 text-purple-400 shrink-0" />
            <span>9. Cookies &amp; Local Client Storage</span>
          </h2>
          <div className="space-y-2 text-gray-300">
            <p>
              SyncTogether minimizes cookie and local storage usage:
            </p>
            <ul className="space-y-2 text-gray-400 list-disc list-inside">
              <li>
                <strong className="text-gray-200">Strictly Essential Website Cookies:</strong> We use secure, HTTP-only authentication session cookies (<code>sb-*-auth-token</code>) to keep you signed in to your account portal.
              </li>
              <li>
                <strong className="text-gray-200">Desktop Client Local Storage:</strong> The desktop app uses local storage (such as <code>SharedPreferences</code> and secure keychain tokens) to remember your login session, UI theme, volume preferences, and your analytics opt-out preference.
              </li>
              <li>
                <strong className="text-gray-200">No Advertising Cookies:</strong> We do not use third-party advertising, retargeting, or cross-site tracking cookies.
              </li>
            </ul>
          </div>
        </section>

        {/* 10. Your Privacy Rights */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <UserCheck className="w-5 h-5 text-purple-400 shrink-0" />
            <span>10. Your Privacy Rights (GDPR, CCPA/CPRA, DPDP)</span>
          </h2>
          <div className="space-y-4 text-gray-300">
            <p>
              Regardless of your geographic location, SyncTogether provides full control over your personal data:
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div className="p-4 sm:p-5 rounded-xl bg-purple-500/5 border border-purple-500/15 space-y-2">
                <div className="flex items-center gap-2 font-semibold text-white text-base">
                  <Download className="w-4 h-4 text-purple-400" />
                  <span>Export Data</span>
                </div>
                <p className="text-gray-400 text-sm">
                  Export a complete JSON archive of your user profile, entitlement level, and subscription records anytime from your Account dashboard.
                </p>
              </div>

              <div className="p-4 sm:p-5 rounded-xl bg-purple-500/5 border border-purple-500/15 space-y-2">
                <div className="flex items-center gap-2 font-semibold text-white text-base">
                  <Trash2 className="w-4 h-4 text-red-400" />
                  <span>Delete Account</span>
                </div>
                <p className="text-gray-400 text-sm">
                  Permanently erase your account, profile, rooms, and all associated database records directly in the desktop app or website.
                </p>
              </div>

              <div className="p-4 sm:p-5 rounded-xl bg-purple-500/5 border border-purple-500/15 space-y-2">
                <div className="flex items-center gap-2 font-semibold text-white text-base">
                  <EyeOff className="w-4 h-4 text-amber-400" />
                  <span>Opt Out of Analytics</span>
                </div>
                <p className="text-gray-400 text-sm">
                  Toggle off product analytics telemetry with one click in the app profile. When disabled, zero usage events are queued or transmitted.
                </p>
              </div>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-3 text-gray-400">
              <strong className="text-white block text-base">California Residents (CCPA / CPRA):</strong>
              <p>
                We do not sell personal information or share it for cross-context behavioral advertising. You have the right to know what personal information is collected, request deletion, request correction, and not be discriminated against for exercising your privacy rights.
              </p>
              <strong className="text-white block text-base pt-1">India Residents (DPDP Act 2023):</strong>
              <p>
                In accordance with the Digital Personal Data Protection Act, 2023, you have the right to access summary information, seek correction or erasure, nominate representatives, and access our grievance redressal mechanism.
              </p>
            </div>
          </div>
        </section>

        {/* 11. Children's Privacy */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <ShieldCheck className="w-5 h-5 text-purple-400 shrink-0" />
            <span>11. Children&apos;s Privacy (COPPA &amp; Global Protections)</span>
          </h2>
          <p className="text-gray-300">
            SyncTogether is not directed to children under the age of 13 (or under 16 in the European Union / UK). We do not knowingly collect personal information from children. If you believe a child has provided us with personal data without parental consent, please contact us immediately at{" "}
            <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="text-purple-300 hover:text-white underline">
              {SITE_CONFIG.supportEmail}
            </a>{" "}
            and we will promptly delete the data.
          </p>
        </section>

        {/* 12. Security Measures */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <Lock className="w-5 h-5 text-purple-400 shrink-0" />
            <span>12. Data Security &amp; Encryption</span>
          </h2>
          <div className="space-y-2 text-gray-400">
            <p className="text-gray-300">
              We implement comprehensive technical and organizational safeguards to protect your data:
            </p>
            <ul className="space-y-2 list-disc list-inside">
              <li><strong>Encryption in Transit:</strong> All network communication is enforced over TLS 1.3 encryption. Real-time audio and video streams use DTLS/SRTP WebRTC protocols.</li>
              <li><strong>Database Protection:</strong> PostgreSQL database security is enforced via strict Row Level Security (RLS) policies ensuring users can only access their authorized data.</li>
              <li><strong>Signed URLs:</strong> Cloud media files utilize short-lived cryptographically signed presigned URLs accessible only to verified room members.</li>
              <li><strong>Zero AV Storage:</strong> Audio and video streams are processed in transient memory by media relays with zero recording to persistent disks.</li>
            </ul>
          </div>
        </section>

        {/* 13. Policy Updates */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <RefreshCw className="w-5 h-5 text-purple-400 shrink-0" />
            <span>13. Changes to This Privacy Policy</span>
          </h2>
          <p className="text-gray-300">
            We may update this Privacy Policy from time to time to reflect improvements to our app, changes in technology, or legal requirements. When updates occur, we will revise the &ldquo;Last Updated&rdquo; date at the top of this page. For significant material changes, we will provide additional notice through the application or website.
          </p>
        </section>

        {/* 14. Contact Us */}
        <section className="space-y-4">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] flex items-center gap-2.5">
            <Globe className="w-5 h-5 text-purple-400 shrink-0" />
            <span>14. Contact Us &amp; Grievance Redressal</span>
          </h2>
          <div className="p-5 sm:p-6 rounded-xl bg-purple-500/10 border border-purple-400/20 text-gray-300 space-y-3">
            <p>
              If you have any questions, concerns, or requests regarding this Privacy Policy, your personal data, or data deletion, please reach out to our Data Protection &amp; Support Team:
            </p>
            <div className="space-y-1.5 text-gray-200">
              <div>
                <strong>Support &amp; Privacy Contact:</strong>{" "}
                <a
                  href={`mailto:${SITE_CONFIG.supportEmail}`}
                  className="text-purple-300 hover:text-white underline"
                >
                  {SITE_CONFIG.supportEmail}
                </a>
              </div>
              <div>
                <strong>Platform Operator:</strong> {SITE_CONFIG.creatorName}
              </div>
              <div>
                <strong>Project Repository:</strong>{" "}
                <a
                  href={SITE_CONFIG.githubRepo}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-purple-300 hover:text-white underline"
                >
                  {SITE_CONFIG.githubRepo}
                </a>
              </div>
            </div>
          </div>
        </section>
      </GlassPanel>
    </div>
  );
}
