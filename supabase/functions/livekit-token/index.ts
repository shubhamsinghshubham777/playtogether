// Mints a LiveKit access token for a room the caller is a member of.
// Secrets (LIVEKIT_API_KEY / LIVEKIT_API_SECRET / LIVEKIT_URL) are set via
// `supabase secrets set --env-file supabase/functions/.env` — never shipped
// to clients. Membership is checked through the caller's own JWT, so RLS
// (room_members select policy) is the source of truth.

import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import { AccessToken } from "npm:livekit-server-sdk@2.17.0";

type TokenRequest = { room_id?: string };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "not_authenticated" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "not_authenticated" }, 401);
  }

  let body: TokenRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const roomId = body.room_id;
  if (!roomId) {
    return json({ error: "room_id_required" }, 400);
  }

  // Visible through RLS only if the caller is a member of a room they can see.
  const { data: membership } = await supabase
    .from("room_members")
    .select("room_id, rooms!inner(ended_at, expires_at)")
    .eq("room_id", roomId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!membership) {
    return json({ error: "not_a_member" }, 403);
  }
  const room = membership.rooms as unknown as {
    ended_at: string | null;
    expires_at: string;
  };
  if (room.ended_at !== null || new Date(room.expires_at) <= new Date()) {
    return json({ error: "room_ended" }, 403);
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", user.id)
    .maybeSingle();

  const token = new AccessToken(
    Deno.env.get("LIVEKIT_API_KEY")!,
    Deno.env.get("LIVEKIT_API_SECRET")!,
    {
      identity: user.id,
      name: profile?.display_name ?? "Watcher",
      // Outlives the longest room (240 min); the room itself gates access.
      ttl: "5h",
    },
  );
  token.addGrant({
    room: roomId,
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: false,
  });

  return json({ token: await token.toJwt(), url: Deno.env.get("LIVEKIT_URL") });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
