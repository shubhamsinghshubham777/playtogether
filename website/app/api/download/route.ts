import { NextResponse } from "next/server";
import { getLatestRelease } from "@/lib/github";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const platformParam = url.searchParams.get("platform")?.toLowerCase();

    const isMac = platformParam === "macos" || platformParam === "mac" || platformParam === "dmg";
    const isWin = platformParam === "windows" || platformParam === "win" || platformParam === "exe";

    const platform = isMac ? "macos" : isWin ? "windows" : "other";

    // Extract cookie for visitor ID
    const cookieHeader = request.headers.get("cookie") || "";
    const visitorMatch = cookieHeader.match(/(?:^|;\s*)pt_vid=([^;]+)/);
    const visitorId = visitorMatch ? decodeURIComponent(visitorMatch[1]) : null;

    const userAgent = request.headers.get("user-agent") || undefined;
    const referrer = request.headers.get("referer") || undefined;

    const release = await getLatestRelease();
    const version = release.version;

    // Track the download asynchronously
    const supabase = createAdminClient();
    try {
      await supabase.from("website_downloads").insert({
        visitor_id: visitorId,
        platform,
        release_version: version,
        referrer: referrer ? referrer.slice(0, 500) : null,
        user_agent: userAgent,
      });
    } catch (err) {
      console.warn("Failed to log website download:", err);
    }

    // Determine target redirect URL
    let redirectUrl = release.htmlUrl;
    if (isMac) {
      redirectUrl = release.macDownloadUrl;
    } else if (isWin) {
      redirectUrl = release.winDownloadUrl;
    }

    return NextResponse.redirect(redirectUrl, { status: 302 });
  } catch (err) {
    console.error("Download route error:", err);
    return NextResponse.redirect(
      "https://github.com/shubhamsinghshubham777/synctogether/releases",
      { status: 302 }
    );
  }
}
