import type { Metadata } from "next";
import { GlassPanel } from "@/components/GlassPanel";
import { PTButton } from "@/components/PTButton";
import { getAllReleases } from "@/lib/github";
import { Tag, Calendar, ExternalLink, Sparkles } from "lucide-react";

export const metadata: Metadata = {
  title: "Changelog & Release Notes",
  description: "Explore the latest updates, features, improvements, and fixes in SyncTogether releases.",
};

export const revalidate = 3600; // ISR hourly

export default async function ChangelogPage() {
  const releases = await getAllReleases();

  const fallbackReleases = [
    {
      id: 1,
      tag_name: "v0.11.0",
      name: "SyncTogether 0.11.0 — Facecams & Persistent Rooms",
      published_at: "2026-08-11T12:00:00Z",
      body: `### New Features
- **Video & Voice Facecams**: Real-time HD Video and low-latency Voice facecams integrated directly into rooms.
- **Persistent Rooms**: Premium hosts can now create named, permanent rooms that never expire.
- **Animated Lottie Reactions**: 24 expressive Google Noto animated emoji reactions floating dynamically over video.
- **Room Dormancy & Nap**: Free rooms nap for 24h upon expiration, resuming local file timestamps seamlessly.

### Performance & Engine
- Upgraded video playback engine with improved hardware decoding on macOS & Windows.
- Clock-skew resistant server time synchronization for millisecond-accurate play/pause events.`,
      html_url: "https://github.com/shubhamsinghshubham777/synctogether/releases",
    },
    {
      id: 2,
      tag_name: "v0.10.0",
      name: "SyncTogether 0.10.0 — Redesigned Violet Glass Interface",
      published_at: "2026-08-04T10:00:00Z",
      body: `### Highlights
- Complete design overhaul featuring violet glassmorphism aesthetics and custom typography (Space Grotesk, Outfit, JetBrains Mono).
- YouTube playback integration with shared seekbar synchronization.
- Real-time room chat with typing presence and per-user avatar styling.`,
      html_url: "https://github.com/shubhamsinghshubham777/synctogether/releases",
    },
  ];

  const displayReleases = releases.length > 0 ? releases : fallbackReleases;

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-12">
      {/* Background Glow */}
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-30" />

      {/* Header */}
      <div className="text-center max-w-2xl mx-auto space-y-4">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-purple-500/10 border border-purple-400/20 text-xs font-mono text-purple-300">
          <Sparkles className="w-3.5 h-3.5 text-amber-300" />
          <span>Product Updates</span>
        </div>
        <h1 className="text-4xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Changelog &amp; <span className="text-gradient-brand">Releases.</span>
        </h1>
        <p className="text-base text-gray-300">
          Stay up to date with the latest features, improvements, and performance upgrades in SyncTogether.
        </p>
      </div>

      {/* Releases Timeline */}
      <div className="space-y-8 relative before:absolute before:inset-0 before:left-4 md:before:left-6 before:w-0.5 before:bg-purple-500/20">
        {displayReleases.map((rel) => {
          const releaseDate = new Date(rel.published_at).toLocaleDateString(
            undefined,
            { year: "numeric", month: "long", day: "numeric" }
          );

          return (
            <div key={rel.id} className="relative pl-10 md:pl-14 space-y-4">
              {/* Timeline Dot */}
              <div className="absolute left-2.5 md:left-4.5 top-5 w-3.5 h-3.5 rounded-full bg-purple-500 border-2 border-[#08070C] shadow-md shadow-purple-500/50" />

              <GlassPanel hoverEffect className="p-6 md:p-8 space-y-6 border-purple-500/20">
                <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 border-b border-white/5 pb-4">
                  <div>
                    <div className="flex items-center gap-2">
                      <Tag className="w-4 h-4 text-purple-400" />
                      <span className="text-xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
                        {(rel.name || rel.tag_name).replace(/_\d+$/, "")}
                      </span>
                    </div>
                    <span className="text-xs text-gray-400 font-mono flex items-center gap-1.5 mt-1">
                      <Calendar className="w-3.5 h-3.5" />
                      {releaseDate}
                    </span>
                  </div>

                  <PTButton
                    href={rel.html_url}
                    variant="outline"
                    size="sm"
                    rightIcon={<ExternalLink className="w-3.5 h-3.5" />}
                  >
                    GitHub Release
                  </PTButton>
                </div>

                {/* Release Body formatted */}
                <div className="prose prose-invert prose-purple max-w-none text-xs sm:text-sm text-gray-300 leading-relaxed whitespace-pre-line">
                  {rel.body}
                </div>
              </GlassPanel>
            </div>
          );
        })}
      </div>
    </div>
  );
}
