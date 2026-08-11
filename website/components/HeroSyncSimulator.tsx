"use client";

import { useState, useEffect, useRef } from "react";
import {
  Play,
  Pause,
  Volume2,
  Users,
  Mic,
  MessageSquare,
  Sparkles,
  ShieldCheck,
} from "lucide-react";

interface ReactionBubble {
  id: number;
  emoji: string;
  x: number;
  y: number;
}

export function HeroSyncSimulator() {
  const [isPlaying, setIsPlaying] = useState(true);
  const [progress, setProgress] = useState(38.4); // percentage
  const [currentTimeSec, setCurrentTimeSec] = useState(3842); // 01:04:02
  const totalDurationSec = 7200; // 02:00:00
  const [reactions, setReactions] = useState<ReactionBubble[]>([]);
  const [activeTab, setActiveTab] = useState<"video" | "youtube">("video");
  const reactionCounter = useRef(0);

  // Simulated playback timer
  useEffect(() => {
    if (!isPlaying) return;
    const interval = setInterval(() => {
      setProgress((prev) => (prev >= 100 ? 0 : prev + 0.15));
      setCurrentTimeSec((prev) => (prev >= totalDurationSec ? 0 : prev + 1));
    }, 1000);
    return () => clearInterval(interval);
  }, [isPlaying]);

  const formatTime = (sec: number) => {
    const hrs = Math.floor(sec / 3600);
    const mins = Math.floor((sec % 3600) / 60);
    const secs = Math.floor(sec % 60);
    return `${hrs.toString().padStart(2, "0")}:${mins
      .toString()
      .padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  };

  const triggerReaction = (emoji: string) => {
    reactionCounter.current += 1;
    const count = reactionCounter.current;
    const newBubble: ReactionBubble = {
      id: count,
      emoji,
      x: 30 + ((count * 17) % 40),
      y: 60 + ((count * 13) % 20),
    };
    setReactions((prev) => [...prev.slice(-8), newBubble]);
    setTimeout(() => {
      setReactions((prev) => prev.filter((r) => r.id !== newBubble.id));
    }, 2200);
  };

  return (
    <div className="relative w-full max-w-5xl mx-auto rounded-2xl md:rounded-3xl p-1.5 md:p-2 bg-gradient-to-b from-purple-500/30 via-purple-900/10 to-transparent shadow-2xl shadow-purple-950/60 border border-purple-400/20">
      {/* Outer Glow */}
      <div className="absolute -inset-1 bg-gradient-to-r from-purple-600/30 to-pink-600/30 rounded-3xl blur-xl opacity-50 -z-10" />

      {/* Main App Container */}
      <div className="bg-[#0B0A14] rounded-xl md:rounded-2xl overflow-hidden border border-white/5 flex flex-col">
        {/* App Titlebar */}
        <div className="bg-[#120F22] px-4 py-3 border-b border-purple-500/15 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-red-500/80" />
            <div className="w-3 h-3 rounded-full bg-amber-500/80" />
            <div className="w-3 h-3 rounded-full bg-emerald-500/80" />
            <span className="text-xs font-mono text-gray-400 ml-2 hidden sm:inline">
              Room <strong className="text-purple-300">#PT-7892</strong>
            </span>
          </div>

          <div className="flex items-center gap-2">
            <span className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-emerald-500/10 text-emerald-300 text-xs font-mono border border-emerald-500/20">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-ping" />
              Sync: 12ms
            </span>
            <span className="hidden sm:flex items-center gap-1 px-2.5 py-1 rounded-full bg-purple-500/10 text-purple-300 text-xs font-mono border border-purple-500/20">
              <Users className="w-3 h-3" /> 4 watching
            </span>
          </div>
        </div>

        {/* Workspace Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-4 min-h-[380px] md:min-h-[460px]">
          {/* Main Video Viewport (3 cols) */}
          <div className="lg:col-span-3 bg-black relative flex flex-col justify-between overflow-hidden group">
            {/* Mock Video Canvas / Background Art */}
            <div
              className={`absolute inset-0 bg-cover bg-center transition-all duration-700 ${
                activeTab === "video"
                  ? "bg-gradient-to-br from-indigo-950 via-purple-950 to-slate-950"
                  : "bg-gradient-to-br from-rose-950 via-slate-950 to-purple-950"
              }`}
            >
              {/* Sci-Fi Cinematic Visual Backdrop Effect */}
              <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-purple-800/25 via-indigo-900/10 to-transparent flex items-center justify-center">
                <div className="text-center space-y-2 opacity-90">
                  <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-purple-500/20 border border-purple-400/30 text-purple-200 text-xs">
                    <Sparkles className="w-3.5 h-3.5 text-amber-300" />
                    {activeTab === "video"
                      ? "Local File: Interstellar_4K_HDR.mkv"
                      : "YouTube: Cyberpunk 2077 Night City Live"}
                  </div>
                  <p className="text-xl md:text-2xl font-bold tracking-tight text-white/90 font-[family-name:var(--font-space-grotesk)]">
                    Synchronized Media Stream
                  </p>
                  <p className="text-xs text-purple-300/70 font-mono">
                    Bitrate: 28.4 Mbps • Direct libmpv Core Engine
                  </p>
                </div>
              </div>
            </div>

            {/* Floating Dynamic Reaction Bubbles */}
            {reactions.map((r) => (
              <div
                key={r.id}
                style={{ left: `${r.x}%`, top: `${r.y}%` }}
                className="absolute text-4xl animate-bounce pointer-events-none transition-all duration-1000 z-30 drop-shadow-[0_4px_12px_rgba(0,0,0,0.8)]"
              >
                {r.emoji}
              </div>
            ))}

            {/* Top Video Overlay Bar */}
            <div className="relative z-10 p-4 flex items-center justify-between bg-gradient-to-b from-black/80 to-transparent">
              <div className="flex gap-2">
                <button
                  onClick={() => setActiveTab("video")}
                  className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                    activeTab === "video"
                      ? "bg-purple-600 text-white shadow-md shadow-purple-600/30"
                      : "bg-white/10 text-gray-300 hover:bg-white/20"
                  }`}
                >
                  Local File Sync
                </button>
                <button
                  onClick={() => setActiveTab("youtube")}
                  className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                    activeTab === "youtube"
                      ? "bg-rose-600 text-white shadow-md shadow-rose-600/30"
                      : "bg-white/10 text-gray-300 hover:bg-white/20"
                  }`}
                >
                  YouTube Sync
                </button>
              </div>

              <div className="flex items-center gap-1.5 text-xs text-gray-300 bg-black/50 px-2.5 py-1 rounded-md backdrop-blur-sm border border-white/10">
                <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
                <span className="hidden sm:inline">Authority:</span>
                <span className="font-semibold text-purple-300">Alex (Host)</span>
              </div>
            </div>

            {/* Bottom Playback Controls */}
            <div className="relative z-10 p-4 bg-gradient-to-t from-black/90 via-black/60 to-transparent space-y-3">
              {/* Progress Bar */}
              <div
                className="relative w-full h-1.5 bg-white/20 hover:h-2 rounded-full cursor-pointer transition-all overflow-hidden"
                onClick={(e) => {
                  const rect = e.currentTarget.getBoundingClientRect();
                  const clickX = e.clientX - rect.left;
                  const newPct = (clickX / rect.width) * 100;
                  setProgress(newPct);
                  setCurrentTimeSec(Math.floor((newPct / 100) * totalDurationSec));
                }}
              >
                <div
                  className="h-full bg-gradient-to-r from-purple-500 to-pink-500 rounded-full relative"
                  style={{ width: `${progress}%` }}
                >
                  <div className="absolute right-0 top-1/2 -translate-y-1/2 w-3 h-3 bg-white rounded-full shadow-md shadow-purple-500/50" />
                </div>
              </div>

              {/* Control Buttons */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <button
                    onClick={() => setIsPlaying(!isPlaying)}
                    className="p-2.5 rounded-full bg-purple-600 hover:bg-purple-500 text-white transition-transform active:scale-95 shadow-md shadow-purple-900/50"
                    aria-label={isPlaying ? "Pause" : "Play"}
                  >
                    {isPlaying ? (
                      <Pause className="w-4 h-4 fill-current" />
                    ) : (
                      <Play className="w-4 h-4 fill-current translate-x-0.5" />
                    )}
                  </button>

                  <span className="text-xs font-mono text-gray-300">
                    {formatTime(currentTimeSec)} / {formatTime(totalDurationSec)}
                  </span>
                </div>

                {/* Quick Reaction Bar */}
                <div className="flex items-center gap-1.5 bg-black/60 px-2.5 py-1 rounded-full border border-white/10 backdrop-blur-md">
                  {["🔥", "🍿", "😂", "💜", "👏"].map((emoji) => (
                    <button
                      key={emoji}
                      onClick={() => triggerReaction(emoji)}
                      className="text-base hover:scale-130 transition-transform active:scale-90 p-0.5 cursor-pointer"
                      title={`Send ${emoji} reaction`}
                    >
                      {emoji}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Side Panel: Facecams & Live Chat (1 col) */}
          <div className="lg:col-span-1 bg-[#120E24] border-t lg:border-t-0 lg:border-l border-purple-500/15 flex flex-col justify-between p-3.5 space-y-4">
            {/* LiveKit Facecams Grid */}
            <div className="space-y-2">
              <div className="flex items-center justify-between text-xs font-bold uppercase tracking-wider text-purple-300/70">
                <span>Facecams (LiveKit)</span>
                <span className="text-[10px] text-emerald-400 font-mono flex items-center gap-1">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
                  HD 1080p
                </span>
              </div>

              <div className="grid grid-cols-2 gap-2">
                {/* Tile 1: Alex */}
                <div className="relative aspect-video rounded-lg bg-purple-950/60 border border-purple-400/30 overflow-hidden flex items-center justify-center">
                  <div className="w-7 h-7 rounded-full bg-gradient-to-tr from-purple-500 to-indigo-500 flex items-center justify-center text-xs font-bold text-white shadow">
                    A
                  </div>
                  <div className="absolute bottom-1 left-1.5 text-[10px] font-medium text-white/90 bg-black/60 px-1 rounded">
                    Alex (Host)
                  </div>
                  <div className="absolute top-1 right-1 p-0.5 rounded bg-emerald-500/20 text-emerald-300">
                    <Mic className="w-2.5 h-2.5" />
                  </div>
                </div>

                {/* Tile 2: Maya */}
                <div className="relative aspect-video rounded-lg bg-pink-950/60 border border-pink-400/30 overflow-hidden flex items-center justify-center ring-1 ring-purple-400/50">
                  <div className="w-7 h-7 rounded-full bg-gradient-to-tr from-pink-500 to-rose-500 flex items-center justify-center text-xs font-bold text-white shadow">
                    M
                  </div>
                  <div className="absolute bottom-1 left-1.5 text-[10px] font-medium text-white/90 bg-black/60 px-1 rounded">
                    Maya
                  </div>
                  <div className="absolute top-1 right-1 p-0.5 rounded bg-emerald-500/20 text-emerald-300 animate-pulse">
                    <Volume2 className="w-2.5 h-2.5" />
                  </div>
                </div>
              </div>
            </div>

            {/* Simulated Live Chat */}
            <div className="flex-1 flex flex-col justify-end space-y-2 border-t border-white/5 pt-3">
              <div className="text-[11px] font-semibold text-gray-400 flex items-center gap-1">
                <MessageSquare className="w-3 h-3 text-purple-400" />
                <span>Room Chat</span>
              </div>

              <div className="space-y-1.5 text-xs">
                <div className="p-1.5 rounded-lg bg-white/5 border border-white/5">
                  <span className="font-semibold text-purple-300">Maya: </span>
                  <span className="text-gray-300">That sound design was unreal 🤯</span>
                </div>
                <div className="p-1.5 rounded-lg bg-white/5 border border-white/5">
                  <span className="font-semibold text-pink-300">Jordan: </span>
                  <span className="text-gray-300">Wait, don&apos;t skip the credits!!</span>
                </div>
                <div className="p-1.5 rounded-lg bg-purple-500/10 border border-purple-500/20 text-[11px] text-purple-200 flex items-center gap-1">
                  <span className="w-1.5 h-1.5 rounded-full bg-purple-400 animate-ping" />
                  <span>Alex is typing...</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
