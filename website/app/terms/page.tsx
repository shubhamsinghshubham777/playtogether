import type { Metadata } from "next";
import { GlassPanel } from "@/components/GlassPanel";
import { SITE_CONFIG } from "@/lib/constants";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "Terms of Service and conditions for using the SyncTogether application and services.",
};

export default function TermsPage() {
  const lastUpdated = "August 11, 2026";

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-12">
      <div className="space-y-3 text-center sm:text-left">
        <span className="text-xs font-mono text-purple-400 font-bold uppercase tracking-wider">
          Legal Agreement
        </span>
        <h1 className="text-4xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Terms of Service
        </h1>
        <p className="text-xs text-gray-400 font-mono">
          Last Updated: {lastUpdated}
        </p>
      </div>

      <GlassPanel className="p-8 sm:p-10 space-y-8 text-sm sm:text-base text-gray-300 leading-relaxed border-purple-500/20">
        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            1. Nature of the Service
          </h2>
          <p>
            SyncTogether is a media synchronization software platform that enables participants to synchronize playback state (play, pause, seek, audio track) for locally stored media files, cloud-shared videos, and public YouTube videos across connected devices.
          </p>
          <div className="p-4 rounded-xl bg-purple-500/10 border border-purple-400/20 text-purple-200 text-sm">
            <strong>Important:</strong> In Local Sync mode, SyncTogether does not host or distribute media files — all participants possess their own local copy. In Cloud Media Sharing mode, room hosts may upload videos for temporary streaming to room guests, subject to automated session expiration.
          </div>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            2. User Accounts &amp; Identities
          </h2>
          <p>
            You may use SyncTogether as a Guest without registration, or authenticate using Google OAuth. You agree to maintain the security of your account and take full responsibility for all activities occurring under your identity.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            3. Acceptable Use
          </h2>
          <p>You agree not to:</p>
          <ul className="list-disc list-inside space-y-2 text-gray-300 text-sm sm:text-base">
            <li>Use the service to broadcast abusive, harmful, or illegal communications.</li>
            <li>Interfere with, overburden, or compromise the integrity of our real-time relay infrastructure.</li>
            <li>Attempt to reverse-engineer server APIs or bypass room limits.</li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            4. Premium Subscriptions &amp; Billing
          </h2>
          <p>
            Paid subscriptions provide enhanced features including persistent rooms, 16-member limits, and video facecams. All subscriptions are processed securely through our authorized Merchant of Record.
          </p>
          <p>
            Subscriptions are billed on a recurring monthly or annual basis. We reserve the right to modify subscription pricing with at least 30 days prior notice.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            5. User Content &amp; Privacy
          </h2>
          <p>
            In Local Sync mode, we do not upload or store your media files or full directory file paths. In Cloud Media Sharing mode, host-uploaded video files are temporarily hosted in encrypted storage and permanently deleted upon room closure or expiry. Room chat messages and quick reactions are session-scoped and purged automatically upon room expiration or closure. For complete details, see our <a href="/privacy" className="text-purple-300 hover:text-white underline">Privacy Policy</a>.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            6. Service Availability &amp; Disclaimer
          </h2>
          <p>
            SyncTogether is provided on an &ldquo;as is&rdquo; and &ldquo;as available&rdquo; basis without warranties of any kind. We do not guarantee uninterrupted or error-free operation.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            7. Governing Law
          </h2>
          <p>
            These Terms shall be governed by and construed in accordance with the laws of India, without regard to its conflict of law provisions.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            8. Contact Us
          </h2>
          <p>
            If you have questions regarding these Terms, please contact us at:{" "}
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
