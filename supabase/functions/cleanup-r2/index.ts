// Cleanup worker for pending R2 deletions and orphaned multipart uploads
import { createClient } from "npm:@supabase/supabase-js@2.58.0";
import {
  S3Client,
  DeleteObjectCommand,
  AbortMultipartUploadCommand,
} from "npm:@aws-sdk/client-s3";

const s3 = new S3Client({
  region: "auto",
  endpoint: Deno.env.get("CF_R2_ENDPOINT") || "https://dummy.r2.cloudflarestorage.com",
  credentials: {
    accessKeyId: Deno.env.get("CF_R2_ACCESS_KEY_ID") || "dummy_key",
    secretAccessKey: Deno.env.get("CF_R2_SECRET_ACCESS_KEY") || "dummy_secret",
  },
});

const bucketName = Deno.env.get("CF_R2_BUCKET_NAME") || "playtogether-media";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL") || "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
);

Deno.serve(async (_req) => {
  let cleanedCount = 0;
  let errorCount = 0;

  // 1. Process pending_r2_deletions queue
  const { data: queue, error: queueError } = await supabaseAdmin
    .from("pending_r2_deletions")
    .select("id, r2_key, upload_id, attempts")
    .order("id", { ascending: true })
    .limit(50);

  if (queue && !queueError) {
    for (const item of queue) {
      try {
        if (item.upload_id) {
          await s3.send(
            new AbortMultipartUploadCommand({
              Bucket: bucketName,
              Key: item.r2_key,
              UploadId: item.upload_id,
            }),
          );
        } else {
          await s3.send(
            new DeleteObjectCommand({
              Bucket: bucketName,
              Key: item.r2_key,
            }),
          );
        }

        await supabaseAdmin.from("pending_r2_deletions").delete().eq("id", item.id);
        cleanedCount++;
      } catch (err: unknown) {
        errorCount++;
        if (item.attempts >= 5) {
          await supabaseAdmin.from("pending_r2_deletions").delete().eq("id", item.id);
        } else {
          await supabaseAdmin
            .from("pending_r2_deletions")
            .update({ attempts: item.attempts + 1 })
            .eq("id", item.id);
        }
      }
    }
  }

  // 2. Sweep stuck uploading rooms (> 2 hours old)
  const twoHoursAgo = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
  const { data: stuckRooms } = await supabaseAdmin
    .from("rooms")
    .select("id, media_r2_key, media_upload_id")
    .eq("media_upload_state", "uploading")
    .lt("media_updated_at", twoHoursAgo);

  if (stuckRooms && stuckRooms.length > 0) {
    for (const room of stuckRooms) {
      if (room.media_upload_id && room.media_r2_key) {
        try {
          await s3.send(
            new AbortMultipartUploadCommand({
              Bucket: bucketName,
              Key: room.media_r2_key,
              UploadId: room.media_upload_id,
            }),
          );
        } catch (_) {}
      }
      await supabaseAdmin.rpc("clear_media_sharing", {
        p_room_id: room.id,
        p_bytes_uploaded: 0,
      });
      cleanedCount++;
    }
  }

  // 3. Sweep expired unclaimed staged media uploads
  const { data: expiredStaged } = await supabaseAdmin
    .from("staged_media_uploads")
    .select("id, r2_key, upload_id")
    .is("claimed_room_id", null)
    .lte("expires_at", new Date().toISOString());

  if (expiredStaged && expiredStaged.length > 0) {
    for (const staged of expiredStaged) {
      if (staged.upload_id && staged.r2_key) {
        try {
          await s3.send(
            new AbortMultipartUploadCommand({
              Bucket: bucketName,
              Key: staged.r2_key,
              UploadId: staged.upload_id,
            }),
          );
        } catch (_) {}
      } else if (staged.r2_key) {
        try {
          await s3.send(
            new DeleteObjectCommand({
              Bucket: bucketName,
              Key: staged.r2_key,
            }),
          );
        } catch (_) {}
      }
      await supabaseAdmin.rpc("clear_staged_upload", {
        p_staged_id: staged.id,
        p_bytes_uploaded: 0,
      });
      cleanedCount++;
    }
  }

  return new Response(
    JSON.stringify({ success: true, cleanedCount, errorCount }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
