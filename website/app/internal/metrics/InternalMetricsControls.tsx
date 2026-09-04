"use client";

import { useState, useEffect, useRef, useTransition } from "react";
import { useRouter } from "next/navigation";
import { RefreshCw, Copy, Check } from "lucide-react";
import { PTButton } from "@/components/PTButton";

interface ControlsProps {
  timestamp: string;
  data: unknown;
}

export function InternalMetricsControls({ timestamp, data }: ControlsProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [mounted, setMounted] = useState<boolean>(false);
  const [autoRefresh, setAutoRefresh] = useState<boolean>(true);
  const [copied, setCopied] = useState<boolean>(false);
  const [secondsRemaining, setSecondsRemaining] = useState<number>(30);
  const secondsRef = useRef<number>(30);

  useEffect(() => {
    setMounted(true);
  }, []);

  const triggerRefresh = () => {
    secondsRef.current = 30;
    setSecondsRemaining(30);
    startTransition(() => {
      router.refresh();
    });
  };

  // Auto-refresh countdown every 30 seconds
  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(() => {
      secondsRef.current -= 1;
      if (secondsRef.current <= 0) {
        triggerRefresh();
      } else {
        setSecondsRemaining(secondsRef.current);
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [autoRefresh]);

  const handleManualRefresh = () => {
    triggerRefresh();
  };

  const handleCopyJson = async () => {
    try {
      await navigator.clipboard.writeText(JSON.stringify(data, null, 2));
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Ignore clipboard error
    }
  };

  const formattedTime = mounted
    ? new Date(timestamp).toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      })
    : "";

  return (
    <div className="flex flex-wrap items-center justify-between gap-4 p-4 rounded-2xl bg-purple-950/20 border border-purple-500/20 backdrop-blur-xl">
      <div className="flex items-center gap-3">
        <div className="flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-400/20 text-emerald-400 text-xs font-mono font-medium">
          <span className="w-2 h-2 rounded-full bg-emerald-400 animate-ping" />
          <span>LOCAL DEV ONLY • CONFIDENTIAL</span>
        </div>
        {mounted && (
          <span
            suppressHydrationWarning
            className="text-xs text-gray-400 font-mono hidden sm:inline"
          >
            Updated at: {formattedTime}
          </span>
        )}
      </div>

      <div className="flex items-center gap-3">
        <label className="flex items-center gap-2 text-xs text-gray-300 cursor-pointer select-none font-mono">
          <input
            type="checkbox"
            checked={autoRefresh}
            onChange={(e) => {
              const isChecked = e.target.checked;
              setAutoRefresh(isChecked);
              secondsRef.current = 30;
              setSecondsRemaining(30);
            }}
            className="rounded border-purple-500/30 bg-purple-900/30 text-purple-600 focus:ring-purple-500/40"
          />
          <span>Auto-refresh ({secondsRemaining}s)</span>
        </label>

        <PTButton
          onClick={handleManualRefresh}
          variant="outline"
          size="sm"
          className="text-xs font-mono"
          leftIcon={
            <RefreshCw
              className={`w-3.5 h-3.5 text-purple-300 ${
                isPending ? "animate-spin" : ""
              }`}
            />
          }
        >
          {isPending ? "Updating..." : "Refresh"}
        </PTButton>

        <PTButton
          onClick={handleCopyJson}
          variant="secondary"
          size="sm"
          className="text-xs font-mono"
          leftIcon={
            copied ? (
              <Check className="w-3.5 h-3.5 text-emerald-400" />
            ) : (
              <Copy className="w-3.5 h-3.5 text-purple-300" />
            )
          }
        >
          {copied ? "Copied JSON" : "Export JSON"}
        </PTButton>
      </div>
    </div>
  );
}
