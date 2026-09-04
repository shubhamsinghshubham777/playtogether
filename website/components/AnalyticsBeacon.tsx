"use client";

import { useEffect, useRef } from "react";
import { usePathname } from "next/navigation";

const COOKIE_NAME = "pt_vid";
const ONE_YEAR_SECONDS = 31536000;

function getOrCreateVisitorId(): string {
  if (typeof document === "undefined") return "";

  const match = document.cookie.match(new RegExp(`(?:^|;\\s*)${COOKIE_NAME}=([^;]+)`));
  if (match && match[1]) {
    return decodeURIComponent(match[1]);
  }

  // Generate anonymous random UUID
  const newId =
    typeof crypto !== "undefined" && crypto.randomUUID
      ? crypto.randomUUID()
      : `v_${Date.now()}_${Math.random().toString(36).slice(2, 11)}`;

  document.cookie = `${COOKIE_NAME}=${encodeURIComponent(
    newId
  )}; path=/; max-age=${ONE_YEAR_SECONDS}; SameSite=Lax`;

  return newId;
}

export function AnalyticsBeacon() {
  const pathname = usePathname();
  const lastTrackedPath = useRef<string | null>(null);

  useEffect(() => {
    if (typeof window === "undefined") return;

    // Avoid double tracking same path in React StrictMode
    if (lastTrackedPath.current === pathname) return;
    lastTrackedPath.current = pathname;

    // Skip internal/admin endpoints from visitor tracking
    if (pathname.startsWith("/internal") || pathname.startsWith("/admin")) {
      return;
    }

    const visitorId = getOrCreateVisitorId();
    if (!visitorId) return;

    const payload = JSON.stringify({
      visitorId,
      pathname,
      referrer: document.referrer || null,
    });

    try {
      if (typeof navigator !== "undefined" && navigator.sendBeacon) {
        const blob = new Blob([payload], { type: "application/json" });
        navigator.sendBeacon("/api/analytics/collect", blob);
      } else {
        fetch("/api/analytics/collect", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: payload,
          keepalive: true,
        }).catch(() => {
          // Non-fatal telemetry catch
        });
      }
    } catch {
      // Non-fatal telemetry catch
    }
  }, [pathname]);

  return null;
}
