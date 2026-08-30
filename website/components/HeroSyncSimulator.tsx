"use client";

import { useState, useEffect, useRef } from "react";
import Image from "next/image";
import {
  Play,
  Pause,
  Mic,
  MicOff,
  Video,
  VideoOff,
  Smile,
  Music,
  Subtitles,
  Tv,
  FolderOpen,
  Volume2,
  VolumeX,
  Copy,
  Check,
  Keyboard,
  Timer,
  MessageSquare,
  MoreVertical,
  ChevronLeft,
  ChevronRight,
  Crown,
  X,
  Send,
} from "lucide-react";

interface ReactionBubble {
  id: number;
  emoji: string;
  x: number;
  y: number;
  rotation: number;
}

const AVAILABLE_EMOJIS = ["🔥", "🍿", "😂", "💜", "👏", "🎉", "🚀", "❤️"];

export function HeroSyncSimulator() {
  const [isPlaying, setIsPlaying] = useState(true);
  const [currentTimeSec, setCurrentTimeSec] = useState(35); // 00:35
  const totalDurationSec = 8673; // 02:24:33
  const [reactions, setReactions] = useState<ReactionBubble[]>([]);
  const [showReactionStrip, setShowReactionStrip] = useState(false);
  const [showChat, setShowChat] = useState(false);
  const [showCams, setShowCams] = useState(true);
  const [micOn, setMicOn] = useState(false);
  const [camOn, setCamOn] = useState(false);
  const [volume, setVolume] = useState(0.85);
  const [isMuted, setIsMuted] = useState(false);
  const [copiedCode, setCopiedCode] = useState(false);
  const [hoverSeekSec, setHoverSeekSec] = useState<number | null>(null);
  const [hoverSeekPct, setHoverSeekPct] = useState<number | null>(null);
  const [chatInput, setChatInput] = useState("");
  const [chatMessages, setChatMessages] = useState([
    { id: 1, sender: "Maya", text: "That sound design was unreal 🤯", color: "text-purple-300" },
    { id: 2, sender: "Guest-0397", text: "Wait, don't skip the credits!!", color: "text-pink-300" },
  ]);

  const [isVisible, setIsVisible] = useState(true);
  const containerRef = useRef<HTMLDivElement>(null);
  const reactionCounter = useRef(0);
  const scrubberRef = useRef<HTMLDivElement>(null);

  // Pause playback timer when component is not in the viewport
  useEffect(() => {
    const el = containerRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        setIsVisible(entry.isIntersecting);
      },
      { threshold: 0.05 }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // Playback timer - active when visible
  useEffect(() => {
    if (!isPlaying || !isVisible) return;
    const interval = setInterval(() => {
      setCurrentTimeSec((prev) => (prev >= totalDurationSec ? 0 : prev + 1));
    }, 1000);
    return () => clearInterval(interval);
  }, [isPlaying, isVisible]);

  const formatTime = (sec: number) => {
    const hrs = Math.floor(sec / 3600);
    const mins = Math.floor((sec % 3600) / 60);
    const secs = Math.floor(sec % 60);
    if (hrs > 0) {
      return `${hrs}:${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
    }
    return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  };

  const triggerReaction = (emoji: string) => {
    reactionCounter.current += 1;
    const count = reactionCounter.current;
    const newBubble: ReactionBubble = {
      id: count,
      emoji,
      x: 35 + ((count * 19) % 35),
      y: 65 + ((count * 11) % 15),
      rotation: ((count * 23) % 40) - 20,
    };
    setReactions((prev) => [...prev.slice(-10), newBubble]);
    setTimeout(() => {
      setReactions((prev) => prev.filter((r) => r.id !== newBubble.id));
    }, 2200);
  };

  const handleCopyCode = () => {
    navigator.clipboard?.writeText?.("WZ2CWX");
    setCopiedCode(true);
    setTimeout(() => setCopiedCode(false), 1600);
  };

  const handleSkip = (seconds: number) => {
    setCurrentTimeSec((prev) =>
      Math.max(0, Math.min(totalDurationSec, prev + seconds))
    );
  };

  const handleScrubberMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!scrubberRef.current) return;
    const rect = scrubberRef.current.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
    const pct = x / rect.width;
    setHoverSeekPct(pct * 100);
    setHoverSeekSec(Math.round(pct * totalDurationSec));
  };

  const handleScrubberClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!scrubberRef.current) return;
    const rect = scrubberRef.current.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
    const pct = x / rect.width;
    setCurrentTimeSec(Math.round(pct * totalDurationSec));
  };

  const handleSendMessage = (e: React.FormEvent) => {
    e.preventDefault();
    if (!chatInput.trim()) return;
    setChatMessages((prev) => [
      ...prev,
      {
        id: Date.now(),
        sender: "You",
        text: chatInput.trim(),
        color: "text-purple-400 font-semibold",
      },
    ]);
    setChatInput("");
  };

  const progressPercent = (currentTimeSec / totalDurationSec) * 100;

  return (
    <div
      ref={containerRef}
      className="relative w-full max-w-5xl mx-auto rounded-2xl md:rounded-3xl p-1 md:p-2 bg-gradient-to-b from-purple-500/25 via-purple-900/10 to-transparent shadow-2xl shadow-purple-950/70 border border-purple-400/20"
    >
      {/* Outer Ambient Glow */}
      <div className="absolute -inset-1 bg-gradient-to-r from-purple-600/25 to-pink-600/25 rounded-3xl blur-2xl opacity-60 -z-10" />

      {/* Main macOS Application Container */}
      <div className="bg-[#0B0A14] rounded-xl md:rounded-2xl overflow-hidden border border-white/10 flex flex-col shadow-2xl select-none">
        {/* macOS App Titlebar */}
        <div className="bg-[#0e0c1a] px-3.5 md:px-4 py-2.5 border-b border-white/5 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-[#FF5F56] border border-black/20" />
            <div className="w-3 h-3 rounded-full bg-[#FFBD2E] border border-black/20" />
            <div className="w-3 h-3 rounded-full bg-[#27C93F] border border-black/20" />
            <span className="text-xs font-medium text-gray-300 ml-2 font-[family-name:var(--font-outfit)]">
              SyncTogether
            </span>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-[11px] font-mono text-purple-300/80 bg-purple-500/10 px-2 py-0.5 rounded-full border border-purple-500/20">
              v0.11.0
            </span>
          </div>
        </div>

        {/* Video Canvas & Floating Overlay Viewport */}
        <div className="relative w-full aspect-[16/10] sm:aspect-[16/9] min-h-[380px] sm:min-h-[440px] md:min-h-[500px] overflow-hidden bg-black flex flex-col justify-between">
          {/* Real Cinematic Background Still */}
          <div className="absolute inset-0 z-0">
            <Image
              src="/sample_movie_frame.jpg"
              alt="Cinematic Movie Still"
              fill
              priority
              sizes="(max-width: 1024px) 100vw, 1024px"
              className="object-cover object-center brightness-90 contrast-105"
            />
            {/* Subtle Vignette Gradients */}
            <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/10 to-black/60 pointer-events-none" />
            <div className="absolute inset-0 bg-gradient-to-r from-black/40 via-transparent to-black/40 pointer-events-none" />
          </div>

          {/* Floating Reactions Overlay */}
          <div className="absolute inset-0 pointer-events-none z-30 overflow-hidden">
            {reactions.map((r) => (
              <div
                key={r.id}
                style={{
                  left: `${r.x}%`,
                  bottom: `${r.y}%`,
                  transform: `rotate(${r.rotation}deg)`,
                }}
                className="absolute text-4xl sm:text-5xl animate-bounce transition-all duration-1000 drop-shadow-[0_4px_16px_rgba(0,0,0,0.9)]"
              >
                {r.emoji}
              </div>
            ))}
          </div>

          {/* TOP BAR OVERLAYS */}
          <div className="relative z-20 p-3 sm:p-4 md:p-5 flex items-start justify-between gap-3">
            {/* Top Left: Room Pill */}
            <div className="backdrop-blur-xl bg-[#141022]/80 border border-white/10 rounded-full px-3 py-1.5 sm:px-4 sm:py-2 shadow-2xl shadow-black/60 flex items-center gap-2 sm:gap-3.5">
              <span className="text-xs sm:text-sm font-semibold text-white font-[family-name:var(--font-space-grotesk)] tracking-tight">
                test room
              </span>

              {/* Room Code Chip */}
              <button
                onClick={handleCopyCode}
                title="Click to copy room code"
                className="bg-[#A78BFA]/15 border border-[#A78BFA]/35 hover:bg-[#A78BFA]/25 transition-all rounded-full px-2 sm:px-2.5 py-0.5 sm:py-1 flex items-center gap-1 sm:gap-1.5 text-[11px] sm:text-xs font-mono font-medium text-[#C9B8FF] tracking-wider cursor-pointer active:scale-95"
              >
                <span>WZ2CWX</span>
                {copiedCode ? (
                  <Check className="w-3 h-3 text-emerald-400" />
                ) : (
                  <Copy className="w-3 h-3 text-purple-300 opacity-80" />
                )}
              </button>

              {/* Keyboard Shortcuts Icon Button */}
              <div
                className="text-gray-400 hover:text-white p-1 rounded-md transition-colors cursor-pointer hidden sm:block"
                title="Keyboard shortcuts"
              >
                <Keyboard className="w-3.5 h-3.5 sm:w-4 sm:h-4" />
              </div>

              {/* Expiry Countdown Timer */}
              <div className="flex items-center gap-1 text-[11px] sm:text-xs font-mono font-medium text-amber-300/90 pl-0.5">
                <Timer className="w-3 h-3 sm:w-3.5 sm:h-3.5 text-amber-400 animate-pulse" />
                <span>02:03 left</span>
              </div>
            </div>

            {/* Top Right: Chat & Overflow Actions */}
            <div className="flex items-center gap-2">
              <button
                onClick={() => setShowChat(!showChat)}
                title="Toggle room chat"
                className={`w-8 h-8 sm:w-9 sm:h-9 md:w-10 md:h-10 rounded-full backdrop-blur-xl border flex items-center justify-center transition-all cursor-pointer shadow-xl shadow-black/40 relative active:scale-95 ${showChat
                  ? "bg-purple-600/90 border-purple-400 text-white shadow-purple-500/30"
                  : "bg-[#141022]/80 border-white/10 hover:border-purple-400/40 text-gray-300 hover:text-white"
                  }`}
              >
                <MessageSquare className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                {!showChat && (
                  <span className="w-2 h-2 rounded-full bg-purple-400 absolute top-1.5 right-1.5 ring-2 ring-[#141022]" />
                )}
              </button>

              <button
                title="More options"
                className="w-8 h-8 sm:w-9 sm:h-9 md:w-10 md:h-10 rounded-full backdrop-blur-xl bg-[#141022]/80 border border-white/10 hover:border-purple-400/40 text-gray-300 hover:text-white flex items-center justify-center transition-all cursor-pointer shadow-xl shadow-black/40 active:scale-95"
              >
                <MoreVertical className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
              </button>
            </div>
          </div>

          {/* LEFT FLOATING FACECAM RAIL (FacecamRail) */}
          <div className="relative z-20 px-3 sm:px-4 md:px-5 flex-1 flex flex-col justify-start">
            <div
              className={`transition-all duration-300 flex flex-col gap-2.5 ${showCams
                ? "opacity-100 translate-x-0"
                : "opacity-0 -translate-x-4 pointer-events-none"
                }`}
            >
              {/* Tile 1: Shubham Singh (Host / Premium / Active Ring) */}
              <div className="w-36 sm:w-40 md:w-44 h-20 sm:h-24 md:h-26 rounded-2xl bg-gradient-to-br from-[#1F1A33] to-[#151021] border-2 border-[#C4A8FF] shadow-[0_0_18px_rgba(196,168,255,0.3)] relative overflow-hidden flex flex-col items-center justify-center p-2">
                {/* User Avatar with Crown */}
                <div className="relative">
                  <div className="w-8 h-8 sm:w-9 sm:h-9 md:w-10 md:h-10 rounded-full bg-gradient-to-tr from-[#60A5FA] to-[#818CF8] flex items-center justify-center text-xs sm:text-sm font-bold text-white shadow-md">
                    S
                  </div>
                  <Crown
                    className="w-3.5 h-3.5 text-amber-400 fill-amber-400 absolute -top-1.5 -right-1 drop-shadow-[0_2px_4px_rgba(0,0,0,0.9)]"
                    aria-label="Premium Host"
                  />
                </div>

                {/* Name & Cam Status */}
                <div className="mt-1 flex items-center gap-1 text-[10px] sm:text-[11px] font-medium text-white/80 font-[family-name:var(--font-outfit)]">
                  <span>Shubham Singh</span>
                  <VideoOff className="w-2.5 h-2.5 text-white/40" />
                </div>

                {/* Mic Muted Badge (Top Right) */}
                <div className="absolute top-1.5 right-1.5 w-4.5 h-4.5 sm:w-5 sm:h-5 rounded-full bg-[#2A1414]/90 border border-red-500/40 text-red-400 flex items-center justify-center shadow-sm">
                  <MicOff className="w-2.5 h-2.5 sm:w-3 sm:h-3" />
                </div>
              </div>

              {/* Tile 2: Guest-0397 */}
              <div className="w-36 sm:w-40 md:w-44 h-20 sm:h-24 md:h-26 rounded-2xl bg-gradient-to-br from-[#1F1A33] to-[#151021] border border-white/10 shadow-lg relative overflow-hidden flex flex-col items-center justify-center p-2">
                {/* User Avatar */}
                <div className="w-8 h-8 sm:w-9 sm:h-9 md:w-10 md:h-10 rounded-full bg-gradient-to-tr from-[#F472B6] to-[#C084FC] flex items-center justify-center text-xs sm:text-sm font-bold text-white shadow-md">
                  G
                </div>

                {/* Name & Cam Status */}
                <div className="mt-1 flex items-center gap-1 text-[10px] sm:text-[11px] font-medium text-white/65 font-[family-name:var(--font-outfit)]">
                  <span>Guest-0397</span>
                  <VideoOff className="w-2.5 h-2.5 text-white/40" />
                </div>

                {/* Mic Muted Badge (Top Right) */}
                <div className="absolute top-1.5 right-1.5 w-4.5 h-4.5 sm:w-5 sm:h-5 rounded-full bg-[#2A1414]/90 border border-red-500/40 text-red-400 flex items-center justify-center shadow-sm">
                  <MicOff className="w-2.5 h-2.5 sm:w-3 sm:h-3" />
                </div>
              </div>
            </div>

            {/* Hide/Show Cams Action Pill */}
            <button
              onClick={() => setShowCams(!showCams)}
              className="mt-2 backdrop-blur-md bg-[#141022]/80 border border-white/10 hover:border-purple-400/40 hover:bg-[#1C1630] transition-all rounded-full px-2.5 sm:px-3 py-1 text-[10px] sm:text-xs font-medium text-white/70 flex items-center gap-1 cursor-pointer w-fit shadow-md active:scale-95"
            >
              {showCams ? (
                <>
                  <ChevronLeft className="w-3 h-3 text-purple-300" />
                  <span>Hide cams</span>
                </>
              ) : (
                <>
                  <ChevronRight className="w-3 h-3 text-purple-300" />
                  <span>Show cams</span>
                </>
              )}
            </button>
          </div>

          {/* FLOATING CHAT OVERLAY PANEL (Toggled via Chat Button) */}
          {showChat && (
            <div className="absolute top-16 sm:top-18 md:top-20 right-3 sm:right-4 md:right-5 w-64 sm:w-72 md:w-80 z-25 backdrop-blur-2xl bg-[#141022]/95 border border-purple-400/30 rounded-2xl p-3.5 shadow-2xl space-y-3 animate-in fade-in slide-in-from-top-2 duration-200">
              <div className="flex items-center justify-between border-b border-white/10 pb-2">
                <div className="flex items-center gap-1.5 text-xs font-semibold text-white">
                  <MessageSquare className="w-3.5 h-3.5 text-purple-400" />
                  <span>Room Chat</span>
                </div>
                <button
                  onClick={() => setShowChat(false)}
                  className="text-gray-400 hover:text-white p-1 rounded transition-colors"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              </div>

              {/* Chat Message List */}
              <div className="space-y-2 max-h-44 overflow-y-auto text-xs pr-1">
                {chatMessages.map((msg) => (
                  <div
                    key={msg.id}
                    className="p-2 rounded-lg bg-white/5 border border-white/5 text-gray-200 leading-snug"
                  >
                    <span className={`font-semibold ${msg.color}`}>
                      {msg.sender}:{" "}
                    </span>
                    <span>{msg.text}</span>
                  </div>
                ))}
                <div className="p-1.5 rounded-lg bg-purple-500/10 border border-purple-500/20 text-[11px] text-purple-200 flex items-center gap-1.5">
                  <span className="w-1.5 h-1.5 rounded-full bg-purple-400 animate-ping" />
                  <span>Alex is typing...</span>
                </div>
              </div>

              {/* Chat Input Bar */}
              <form onSubmit={handleSendMessage} className="flex gap-1.5 pt-1">
                <input
                  type="text"
                  value={chatInput}
                  onChange={(e) => setChatInput(e.target.value)}
                  placeholder="Send a chat message..."
                  className="flex-1 bg-black/40 border border-white/10 rounded-lg px-2.5 py-1.5 text-xs text-white placeholder-gray-500 focus:outline-none focus:border-purple-400"
                />
                <button
                  type="submit"
                  className="p-1.5 rounded-lg bg-purple-600 hover:bg-purple-500 text-white transition-colors cursor-pointer"
                >
                  <Send className="w-3.5 h-3.5" />
                </button>
              </form>
            </div>
          )}

          {/* BOTTOM FLOATING PLAYER CONTROL DOCK (RoomControlBar) */}
          <div className="relative z-20 p-3 sm:p-4 md:p-5 flex flex-col items-center">
            {/* Reaction Selector Strip (Popup above dock) */}
            {showReactionStrip && (
              <div className="mb-2 backdrop-blur-2xl bg-[#141022]/90 border border-purple-400/30 px-3 py-1.5 rounded-full flex items-center gap-2 shadow-2xl animate-in fade-in slide-in-from-bottom-2 duration-150">
                {AVAILABLE_EMOJIS.map((emoji) => (
                  <button
                    key={emoji}
                    onClick={() => triggerReaction(emoji)}
                    className="text-lg hover:scale-135 transition-transform active:scale-95 cursor-pointer p-0.5"
                    title={`React ${emoji}`}
                  >
                    {emoji}
                  </button>
                ))}
              </div>
            )}

            {/* Main Glass Control Panel */}
            <div className="w-full max-w-3xl backdrop-blur-2xl bg-[#141022]/85 border border-white/10 rounded-2xl md:rounded-3xl px-3 sm:px-5 md:px-6 py-2.5 sm:py-3.5 md:py-4 shadow-2xl shadow-black/80 space-y-2 sm:space-y-3">
              {/* Row 1: Timeline Scrubber */}
              <div className="flex items-center gap-2.5 sm:gap-4">
                <span className="text-xs sm:text-[13px] font-mono font-medium text-white min-w-[38px]">
                  {formatTime(currentTimeSec)}
                </span>

                {/* Scrubber Bar with Hover Preview Chip */}
                <div
                  ref={scrubberRef}
                  onMouseMove={handleScrubberMouseMove}
                  onMouseLeave={() => {
                    setHoverSeekSec(null);
                    setHoverSeekPct(null);
                  }}
                  onClick={handleScrubberClick}
                  className="relative flex-1 h-1.5 sm:h-2 bg-white/15 hover:h-2.5 rounded-full cursor-pointer transition-all group"
                >
                  {/* Hover Seek Preview Chip */}
                  {hoverSeekSec !== null && hoverSeekPct !== null && (
                    <div
                      style={{ left: `${hoverSeekPct}%` }}
                      className="absolute -top-7 -translate-x-1/2 px-2 py-0.5 rounded bg-[#161226] border border-white/20 text-[10px] font-mono text-purple-200 shadow-xl pointer-events-none"
                    >
                      {formatTime(hoverSeekSec)}
                    </div>
                  )}

                  {/* Active Progress Fill */}
                  <div
                    className="h-full bg-gradient-to-r from-[#8B5CF6] via-[#A855F7] to-[#C084FC] rounded-full relative"
                    style={{ width: `${progressPercent}%` }}
                  >
                    {/* Glowing White Thumb Dot */}
                    <div className="absolute right-0 top-1/2 -translate-y-1/2 w-2.5 h-2.5 sm:w-3.5 sm:h-3.5 bg-white rounded-full shadow-[0_0_8px_rgba(255,255,255,0.9),0_0_16px_rgba(168,85,247,0.8)] transform scale-100 group-hover:scale-125 transition-transform" />
                  </div>
                </div>

                <span className="text-xs sm:text-[13px] font-mono text-white/50 min-w-[50px] text-right">
                  {formatTime(totalDurationSec)}
                </span>
              </div>

              {/* Row 2: Control Action Buttons (Left / Center / Right) */}
              <div className="flex items-center justify-between pt-0.5">
                {/* Left Section: AV Toggles & Reaction Trigger */}
                <div className="flex items-center gap-1 sm:gap-2">
                  {/* Mic Toggle */}
                  <button
                    onClick={() => setMicOn(!micOn)}
                    title={micOn ? "Mute mic" : "Unmute mic"}
                    className={`p-1.5 sm:p-2 rounded-xl transition-all cursor-pointer ${micOn
                      ? "bg-purple-600/30 text-purple-300 border border-purple-400/40"
                      : "text-gray-400 hover:text-white hover:bg-white/10"
                      }`}
                  >
                    {micOn ? (
                      <Mic className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                    ) : (
                      <MicOff className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                    )}
                  </button>

                  {/* Camera Toggle */}
                  <button
                    onClick={() => setCamOn(!camOn)}
                    title={camOn ? "Turn camera off" : "Turn camera on"}
                    className={`p-1.5 sm:p-2 rounded-xl transition-all cursor-pointer ${camOn
                      ? "bg-purple-600/30 text-purple-300 border border-purple-400/40"
                      : "text-gray-400 hover:text-white hover:bg-white/10"
                      }`}
                  >
                    {camOn ? (
                      <Video className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                    ) : (
                      <VideoOff className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                    )}
                  </button>

                  {/* Reaction Button */}
                  <button
                    onClick={() => {
                      setShowReactionStrip(!showReactionStrip);
                      triggerReaction(
                        AVAILABLE_EMOJIS[
                        Math.floor(Math.random() * AVAILABLE_EMOJIS.length)
                        ]
                      );
                    }}
                    title="Send reaction"
                    className={`p-1.5 sm:p-2 rounded-xl transition-all cursor-pointer ${showReactionStrip
                      ? "bg-purple-600/30 text-purple-300 border border-purple-400/40"
                      : "text-gray-400 hover:text-white hover:bg-white/10"
                      }`}
                  >
                    <Smile className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                  </button>

                  {/* Divider */}
                  <div className="w-px h-5 bg-white/10 mx-0.5 hidden sm:block" />

                  {/* Audio Tracks */}
                  <button
                    title="Audio tracks"
                    className="p-1.5 sm:p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/10 transition-all cursor-pointer hidden sm:block"
                  >
                    <Music className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                  </button>

                  {/* Subtitles */}
                  <button
                    title="Subtitles"
                    className="p-1.5 sm:p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/10 transition-all cursor-pointer hidden sm:block"
                  >
                    <Subtitles className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                  </button>
                </div>

                {/* Center Section: Rewind 10, Big Glowing Play Button, Forward 10 */}
                <div className="flex items-center gap-2 sm:gap-4">
                  {/* Replay 10s */}
                  <button
                    onClick={() => handleSkip(-10)}
                    title="Skip backward 10s"
                    className="p-1.5 sm:p-2 rounded-xl text-gray-300 hover:text-white hover:bg-white/10 transition-all cursor-pointer active:-rotate-45"
                  >
                    <svg
                      className="w-5 h-5 sm:w-6 sm:h-6"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" />
                      <path d="M3 3v5h5" />
                      <text
                        x="12"
                        y="15.5"
                        textAnchor="middle"
                        fontSize="7"
                        fontWeight="bold"
                        fill="currentColor"
                        stroke="none"
                        fontFamily="monospace"
                      >
                        10
                      </text>
                    </svg>
                  </button>

                  {/* Large Glowing Purple Play/Pause Button */}
                  <button
                    onClick={() => setIsPlaying(!isPlaying)}
                    title={isPlaying ? "Pause" : "Play"}
                    className="w-10 h-10 sm:w-11 sm:h-11 md:w-12 md:h-12 rounded-full bg-gradient-to-tr from-[#8B5CF6] via-[#9333EA] to-[#A855F7] text-white flex items-center justify-center shadow-[0_0_24px_rgba(168,85,247,0.6)] hover:shadow-[0_0_32px_rgba(168,85,247,0.9)] hover:scale-105 active:scale-95 transition-all cursor-pointer"
                    aria-label={isPlaying ? "Pause" : "Play"}
                  >
                    {isPlaying ? (
                      <Pause className="w-5 h-5 fill-current" />
                    ) : (
                      <Play className="w-5 h-5 fill-current translate-x-0.5" />
                    )}
                  </button>

                  {/* Forward 10s */}
                  <button
                    onClick={() => handleSkip(10)}
                    title="Skip forward 10s"
                    className="p-1.5 sm:p-2 rounded-xl text-gray-300 hover:text-white hover:bg-white/10 transition-all cursor-pointer active:rotate-45"
                  >
                    <svg
                      className="w-5 h-5 sm:w-6 sm:h-6"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <path d="M21 12a9 9 0 1 1-9-9 9.75 9.75 0 0 1 6.74 2.74L21 8" />
                      <path d="M21 3v5h-5" />
                      <text
                        x="12"
                        y="15.5"
                        textAnchor="middle"
                        fontSize="7"
                        fontWeight="bold"
                        fill="currentColor"
                        stroke="none"
                        fontFamily="monospace"
                      >
                        10
                      </text>
                    </svg>
                  </button>
                </div>

                {/* Right Section: Stream Source, Open File, Volume */}
                <div className="flex items-center gap-1 sm:gap-2">
                  {/* Switch Stream Source */}
                  <button
                    title="Switch source (YouTube / Local)"
                    className="p-1.5 sm:p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/10 transition-all cursor-pointer hidden sm:block"
                  >
                    <Tv className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                  </button>

                  {/* Open File */}
                  <button
                    title="Open local file"
                    className="p-1.5 sm:p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/10 transition-all cursor-pointer hidden sm:block"
                  >
                    <FolderOpen className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                  </button>

                  {/* Volume Control */}
                  <div className="flex items-center gap-1 sm:gap-1.5 pl-1">
                    <button
                      onClick={() => setIsMuted(!isMuted)}
                      title={isMuted || volume === 0 ? "Unmute" : "Mute"}
                      className="p-1.5 sm:p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/10 transition-all cursor-pointer"
                    >
                      {isMuted || volume === 0 ? (
                        <VolumeX className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                      ) : (
                        <Volume2 className="w-4 h-4 sm:w-4.5 sm:h-4.5" />
                      )}
                    </button>

                    {/* Volume Slider Track */}
                    <div
                      onClick={(e) => {
                        const rect = e.currentTarget.getBoundingClientRect();
                        const x = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
                        const newVol = Number((x / rect.width).toFixed(2));
                        setVolume(newVol);
                        if (isMuted && newVol > 0) setIsMuted(false);
                      }}
                      className="w-14 sm:w-20 md:w-24 h-1.5 bg-white/15 hover:h-2 rounded-full overflow-hidden relative cursor-pointer hidden xs:block transition-all"
                    >
                      <div
                        className="h-full bg-gradient-to-r from-purple-500 to-pink-500 rounded-full"
                        style={{ width: `${isMuted ? 0 : volume * 100}%` }}
                      />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
