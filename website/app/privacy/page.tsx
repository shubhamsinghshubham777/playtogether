import type { Metadata } from "next";
import { GlassPanel } from "@/components/GlassPanel";
import { SITE_CONFIG } from "@/lib/constants";
import { ShieldCheck } from "lucide-react";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "Learn how SyncTogether protects your privacy, your media data, and your account information.",
};

export default function PrivacyPage() {
  const lastUpdated = "August 11, 2026";

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-12">
      <div className="space-y-3 text-center sm:text-left">
        <span className="text-xs font-mono text-purple-400 font-bold uppercase tracking-wider">
          Privacy &amp; Data Protection
        </span>
        <h1 className="text-4xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Privacy Policy
        </h1>
        <p className="text-xs text-gray-400 font-mono">
          Last Updated: {lastUpdated}
        </p>
      </div>

      <GlassPanel className="p-8 sm:p-10 space-y-8 text-sm text-gray-300 leading-relaxed border-purple-500/20">
        <section className="space-y-3">
          <div className="p-4 rounded-xl bg-purple-500/10 border border-purple-400/20 space-y-2 text-purple-200 text-xs">
            <div className="flex items-center gap-2 font-bold text-white text-sm">
              <ShieldCheck className="w-4 h-4 text-emerald-400" />
              <span>Our Privacy Pledge</span>
            </div>
            <p>
              SyncTogether is designed around privacy by architecture: your local media file contents, absolute disk file paths, and video bytes never leave your device. We do not sell user data.
            </p>
          </div>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            1. Information We Collect
          </h2>
          <ul className="space-y-2.5 text-xs text-gray-300">
            <li>
              <strong className="text-white">Account Information:</strong> When you sign in with Google, we store your email address, display name, and avatar URL securely for authentication.
            </li>
            <li>
              <strong className="text-white">Crash &amp; Diagnostic Reports:</strong> Device model, OS version, and stack traces to ensure app stability. Does not collect personal data.
            </li>
            <li>
              <strong className="text-white">Product Analytics:</strong> Anonymous telemetry to measure feature usage. You can toggle this off at any time in the desktop app under <em>Profile &rarr; &ldquo;Share usage data&rdquo;</em>.
            </li>
            <li>
              <strong className="text-white">Voice &amp; Video Streams:</strong> Relayed in real-time over encrypted connections. Video and audio are <strong>never recorded or stored</strong> on our servers.
            </li>
            <li>
              <strong className="text-white">Room Chat &amp; Reactions:</strong> Temporary messages and emoji reactions are stored strictly for the duration of the room and purged automatically upon room expiry.
            </li>
            <li>
              <strong className="text-white">Payment Information:</strong> Handled entirely by our authorized Merchant of Record. We never see or store your credit card or UPI details.
            </li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            2. What We Explicitly DO NOT Collect
          </h2>
          <ul className="space-y-1.5 text-xs text-gray-400 list-disc list-inside">
            <li>Your local media files or video streams</li>
            <li>Your local file paths or directory structure</li>
            <li>Continuous IP location logs</li>
            <li>Voice or webcam audio/video recordings</li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            3. Infrastructure &amp; Security
          </h2>
          <p className="text-xs">
            We partner with industry-standard, privacy-compliant infrastructure providers to operate the service:
          </p>
          <ul className="space-y-1 text-xs text-gray-400 list-disc list-inside">
            <li><strong>Authentication &amp; Cloud Database:</strong> Secure user accounts and real-time synchronization channels.</li>
            <li><strong>Real-time Media Relays:</strong> Low-latency encrypted facecam and voice streaming.</li>
            <li><strong>Payment Gateway &amp; Billing:</strong> Compliant Merchant of Record payment processing and subscription management.</li>
            <li><strong>Diagnostics &amp; Telemetry:</strong> Crash diagnostics and privacy-conscious product metrics (opt-out available).</li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            4. Your Rights &amp; Data Deletion
          </h2>
          <p>
            You have full control over your personal information:
          </p>
          <ul className="space-y-1.5 text-xs text-gray-400 list-disc list-inside">
            <li><strong>Delete Account:</strong> You can permanently delete your account and all associated records directly inside the SyncTogether desktop app.</li>
            <li><strong>Export Data:</strong> You can export a full JSON dump of your profile and subscription record at any time from your Account dashboard.</li>
            <li><strong>Opt Out:</strong> You can disable analytics telemetry in one click.</li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            5. Cookies
          </h2>
          <p>
            The SyncTogether website uses only strictly essential cookies required to manage your authenticated user session. We do not use third-party advertising or cross-site tracking cookies.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            6. Contact
          </h2>
          <p>
            For any privacy inquiries or data requests, reach us at:{" "}
            <a
              href={`mailto:${SITE_CONFIG.supportEmail}`}
              className="text-purple-300 hover:text-white underline"
            >
              {SITE_CONFIG.supportEmail}
            </a>.
          </p>
        </section>
      </GlassPanel>
    </div>
  );
}
