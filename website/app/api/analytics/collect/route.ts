import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const { visitorId, pathname, referrer } = body;

    if (!visitorId || typeof visitorId !== "string" || visitorId.length > 128) {
      return NextResponse.json({ error: "Invalid visitor ID" }, { status: 400 });
    }

    const userAgent = request.headers.get("user-agent") || undefined;
    const cleanPath = typeof pathname === "string" ? pathname.slice(0, 255) : "/";
    const cleanRef = typeof referrer === "string" ? referrer.slice(0, 500) : null;

    const supabase = createAdminClient();

    // 1. Fetch existing visitor if present
    const { data: existingVisitor, error: fetchErr } = await supabase
      .from("website_visitors")
      .select("visitor_id, pageviews_count")
      .eq("visitor_id", visitorId)
      .maybeSingle();

    if (fetchErr) {
      console.warn("Analytics fetch visitor warning:", fetchErr.message);
    }

    if (!existingVisitor) {
      // New unique visitor
      await supabase.from("website_visitors").insert({
        visitor_id: visitorId,
        first_seen_at: new Date().toISOString(),
        last_seen_at: new Date().toISOString(),
        pageviews_count: 1,
        first_referrer: cleanRef,
        first_path: cleanPath,
        user_agent: userAgent,
      });
    } else {
      // Existing returning visitor
      await supabase
        .from("website_visitors")
        .update({
          last_seen_at: new Date().toISOString(),
          pageviews_count: (existingVisitor.pageviews_count || 1) + 1,
        })
        .eq("visitor_id", visitorId);
    }

    // 2. Insert pageview record
    await supabase.from("website_pageviews").insert({
      visitor_id: visitorId,
      pathname: cleanPath,
      referrer: cleanRef,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Analytics collection error:", err);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
