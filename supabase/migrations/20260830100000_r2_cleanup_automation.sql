-- R2 Storage Cleanup Automation & Leak Prevention
-- Triggers for room/staged deletions, periodic cleanup invocation via pg_net, and pg_cron scheduling.

-- 1. Extensions
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- 2. Trigger on public.rooms (BEFORE DELETE)
-- Ensures that whenever a room is deleted (via delete_room RPC, CASCADE, or manual deletion),
-- any attached R2 media or multipart upload session is immediately queued to pending_r2_deletions.
create or replace function public.trig_queue_room_media_deletion()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.media_r2_key is not null or old.media_upload_id is not null then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (old.media_r2_key, old.media_upload_id);
  end if;

  -- Clear active upload lock on any profile holding this room
  update public.profiles set
    active_upload_room_id = null,
    active_upload_started_at = null
  where active_upload_room_id = old.id;

  return old;
end;
$$;

drop trigger if exists on_room_deleted_cleanup_media on public.rooms;
create trigger on_room_deleted_cleanup_media
  before delete on public.rooms
  for each row execute function public.trig_queue_room_media_deletion();

-- 3. Trigger on public.staged_media_uploads (BEFORE DELETE)
-- Ensures that when an unclaimed staged upload is deleted, its R2 object/upload session is queued.
create or replace function public.trig_queue_staged_media_deletion()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.claimed_room_id is null and (old.r2_key is not null or old.upload_id is not null) then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (old.r2_key, old.upload_id);
  end if;

  -- Clear active staged upload lock on the profile
  update public.profiles set
    active_upload_staged_id = null,
    active_upload_started_at = null
  where active_upload_staged_id = old.id;

  return old;
end;
$$;

drop trigger if exists on_staged_media_deleted_cleanup on public.staged_media_uploads;
create trigger on_staged_media_deleted_cleanup
  before delete on public.staged_media_uploads
  for each row execute function public.trig_queue_staged_media_deletion();

-- 4. App settings default configuration for R2 cleanup worker
insert into public.app_settings (key, value)
values ('r2_cleanup', '{"enabled": true, "endpoint_url": null, "service_role_key": null}'::jsonb)
on conflict (key) do nothing;

-- 5. Helper function: invoke_r2_cleanup()
-- Evaluates whether cleanup work exists and invokes the cleanup-r2 edge function via pg_net if configured.
create or replace function public.invoke_r2_cleanup()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_settings jsonb;
  v_enabled boolean;
  v_endpoint text;
  v_auth_header text;
  v_has_pending boolean;
begin
  -- 1. Fast check: is there any cleanup work pending?
  select (
    exists (select 1 from public.pending_r2_deletions)
    or exists (
      select 1 from public.rooms
      where media_upload_state = 'uploading'
        and media_updated_at < now() - interval '2 hours'
    )
    or exists (
      select 1 from public.staged_media_uploads
      where claimed_room_id is null
        and expires_at <= now()
    )
  ) into v_has_pending;

  if not v_has_pending then
    return;
  end if;

  -- 2. Read app settings
  select value into v_settings from public.app_settings where key = 'r2_cleanup';
  v_enabled := coalesce((v_settings->>'enabled')::boolean, true);
  if not v_enabled then
    return;
  end if;

  v_endpoint := nullif(trim(v_settings->>'endpoint_url'), '');
  v_auth_header := nullif(trim(v_settings->>'service_role_key'), '');

  -- 3. Trigger HTTP POST via pg_net if endpoint is configured
  if v_endpoint is not null then
    perform net.http_post(
      url := v_endpoint,
      headers := case
        when v_auth_header is not null then
          jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_auth_header
          )
        else
          jsonb_build_object('Content-Type', 'application/json')
      end,
      body := '{}'::jsonb
    );
  end if;
exception when others then
  raise warning 'invoke_r2_cleanup failed: %', sqlerrm;
end $$;

revoke execute on function public.invoke_r2_cleanup() from public, anon;
grant execute on function public.invoke_r2_cleanup() to authenticated, service_role;

-- 6. Schedule recurring 5-minute cleanup job via pg_cron
do $$
begin
  perform cron.unschedule('invoke-r2-cleanup');
exception when others then
  null;
end $$;

select cron.schedule('invoke-r2-cleanup', '*/5 * * * *', $$ select public.invoke_r2_cleanup(); $$);
