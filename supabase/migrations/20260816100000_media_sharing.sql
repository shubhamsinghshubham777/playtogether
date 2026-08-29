-- Media Sharing via Cloudflare R2
-- Schema, constraints, bandwidth tracking, concurrency locks, and RPCs.

-- 1. App settings (Global kill-switch and platform defaults)
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.app_settings (key, value)
values ('media_sharing', '{"enabled": true, "free_tier_max_file_bytes": 2147483648, "premium_max_file_bytes": 10737418240}'::jsonb)
on conflict (key) do nothing;

alter table public.app_settings enable row level security;
revoke all on public.app_settings from public, anon;
grant select on public.app_settings to authenticated;

-- 2. Schema changes on rooms
alter table public.rooms
  add column media_file_size bigint
    check (media_file_size > 0),
  add column media_r2_key text
    check (char_length(media_r2_key) between 1 and 512),
  add column media_upload_id text
    check (char_length(media_upload_id) between 1 and 512),
  add column media_upload_state text not null default 'none'
    check (media_upload_state in ('none', 'uploading', 'ready', 'failed')),
  add column media_sharing_level text not null default 'none'
    check (media_sharing_level in ('none', 'limited', 'full'));

-- Update shape constraint to ensure R2 columns are strictly consistent
alter table public.rooms
  drop constraint if exists rooms_media_shape_chk;

alter table public.rooms
  add constraint rooms_media_shape_chk check (
    case media_kind
      when 'none' then
        media_name is null and media_duration_ms is null and media_url is null
        and media_r2_key is null and media_file_size is null and media_upload_id is null
        and media_upload_state = 'none'
      when 'local' then
        media_name is not null and media_url is null
        and (
          (media_upload_state = 'none' and media_r2_key is null and media_file_size is null and media_upload_id is null)
          or (media_upload_state in ('uploading', 'failed'))
          or (media_upload_state = 'ready' and media_r2_key is not null and media_file_size is not null and media_upload_id is null)
        )
      when 'youtube' then
        media_url is not null and media_r2_key is null and media_file_size is null
        and media_upload_id is null and media_upload_state = 'none'
      else false
    end
  );

-- 3. Schema changes on profiles (Quota, Cooldowns & Concurrency Lock)
alter table public.profiles
  add column r2_upload_bytes_7d bigint not null default 0,
  add column r2_upload_window_start timestamptz not null default now(),
  add column r2_consecutive_aborts int not null default 0,
  add column r2_cooldown_until timestamptz,
  add column active_upload_room_id uuid references public.rooms(id) on delete set null,
  add column active_upload_started_at timestamptz;

-- 4. Schema changes on tier_limits
alter table public.tier_limits
  add column media_sharing text not null default 'none'
    check (media_sharing in ('none', 'limited', 'full')),
  add column media_sharing_weekly_bytes bigint not null default 0;

update public.tier_limits set media_sharing = 'none', media_sharing_weekly_bytes = 0 where tier = 'guest';
update public.tier_limits set media_sharing = 'limited', media_sharing_weekly_bytes = 2684354560 where tier = 'free';
update public.tier_limits set media_sharing = 'full', media_sharing_weekly_bytes = 0 where tier = 'premium';

-- 5. Pending R2 Deletions Queue
create table public.pending_r2_deletions (
  id bigint generated always as identity primary key,
  r2_key text not null,
  upload_id text, -- Non-null if an incomplete multipart upload needs aborting
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.pending_r2_deletions enable row level security;
revoke all on public.pending_r2_deletions from public, anon, authenticated;

-- 6. Update list_my_rooms() RPC
drop function if exists public.list_my_rooms();

create function public.list_my_rooms()
returns table (
  id uuid,
  code text,
  name text,
  created_by uuid,
  created_at timestamptz,
  duration_minutes int,
  expires_at timestamptz,
  ended_at timestamptz,
  resumable_until timestamptz,
  persistent boolean,
  dormant_hours int,
  av_level text,
  max_members int,
  transport_lock boolean,
  media_kind text,
  media_name text,
  media_duration_ms bigint,
  media_url text,
  media_updated_at timestamptz,
  media_position_ms bigint,
  media_position_at timestamptz,
  media_file_size bigint,
  media_r2_key text,
  media_upload_state text,
  media_sharing_level text,
  state text,
  role text,
  member_count int,
  is_owner boolean,
  is_member boolean
)
language sql stable security definer set search_path = ''
as $$
  select
    r.id, r.code, r.name, r.created_by, r.created_at, r.duration_minutes,
    r.expires_at, r.ended_at, r.resumable_until, r.persistent, r.dormant_hours,
    r.av_level, r.max_members, r.transport_lock,
    r.media_kind, r.media_name, r.media_duration_ms, r.media_url, r.media_updated_at,
    r.media_position_ms, r.media_position_at,
    r.media_file_size, r.media_r2_key, r.media_upload_state, r.media_sharing_level,
    public.room_state(r),
    m.role,
    (select count(*)::int from public.room_members x where x.room_id = r.id),
    r.created_by = (select auth.uid()),
    m.user_id is not null
  from public.rooms r
  left join public.room_members m
    on m.room_id = r.id and m.user_id = (select auth.uid())
  where (select auth.uid()) is not null
    and (m.user_id is not null or r.created_by = (select auth.uid()))
    and public.room_state(r) in ('live', 'dormant')
  order by (public.room_state(r) = 'live') desc, r.created_at desc;
$$;

revoke execute on function public.list_my_rooms() from public, anon;
grant execute on function public.list_my_rooms() to authenticated;

-- 7. Update create_room to populate media_sharing_level
create or replace function public.create_room(p_name text, p_duration_minutes int)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tier text;
  v_limits public.tier_limits;
  v_held int;
  v_code text;
  v_room public.rooms;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  v_tier := public.effective_tier(v_uid);
  select * into v_limits from public.tier_limits where tier = v_tier;

  if p_duration_minutes is null
     or p_duration_minutes < 5
     or p_duration_minutes > v_limits.max_session_minutes then
    raise exception 'invalid_duration';
  end if;

  select count(*) into v_held from public.rooms r
    where r.created_by = v_uid and public.room_state(r) in ('live', 'dormant');
  if v_held >= v_limits.max_live_rooms then
    if v_tier = 'guest' then
      raise exception 'guest_room_limit';
    end if;
    raise exception 'room_limit_reached';
  end if;

  if v_limits.persistent_room_cap > 0 then
    select count(*) into v_held from public.rooms r
      where r.created_by = v_uid and r.persistent;
    if v_held >= v_limits.persistent_room_cap then
      raise exception 'room_limit_reached';
    end if;
  end if;

  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
      into v_code from generate_series(1, 6);
    exit when not exists (select 1 from public.rooms where code = v_code);
  end loop;

  insert into public.rooms (
    code, name, created_by, duration_minutes, expires_at,
    persistent, dormant_hours, av_level, max_members, media_sharing_level)
  values (
    v_code,
    coalesce(nullif(left(trim(p_name), 60), ''), 'Watch party'),
    v_uid,
    p_duration_minutes,
    now() + make_interval(mins => p_duration_minutes),
    v_limits.persistent_room_cap > 0,
    v_limits.dormant_hours,
    v_limits.av_level,
    v_limits.max_members,
    v_limits.media_sharing)
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host');

  return v_room;
end $$;

-- 8. Update set_room_media to clean up R2 objects on media switch
create or replace function public.set_room_media(
  p_room_id uuid,
  p_kind text,
  p_name text default null,
  p_duration_ms bigint default null,
  p_url text default null)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_url text := nullif(trim(coalesce(p_url, '')), '');
  v_duration bigint := case when p_duration_ms >= 0 then p_duration_ms end;
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = v_uid and role = 'host') then
    raise exception 'not_host';
  end if;
  if not public.is_room_live(p_room_id) then
    raise exception 'room_ended';
  end if;

  if v_kind not in ('none', 'local', 'youtube')
     or (v_kind = 'local' and v_name is null)
     or (v_kind = 'youtube' and v_url is null) then
    raise exception 'invalid_media';
  end if;

  select * into v_room from public.rooms where id = p_room_id;

  -- Normalize to the shape constraint before writing.
  if v_kind = 'none' then
    v_name := null;
    v_url := null;
    v_duration := null;
  elsif v_kind = 'local' then
    v_url := null;
  end if;

  -- If switching away from local or changing local file, purge previous R2 object/upload
  if (v_room.media_r2_key is not null or v_room.media_upload_id is not null)
     and (v_kind != 'local' or v_name != v_room.media_name) then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);

    update public.rooms set
      media_r2_key = null,
      media_upload_id = null,
      media_file_size = null,
      media_upload_state = 'none'
    where id = p_room_id;
  end if;

  update public.rooms set
    media_kind = v_kind,
    media_name = left(v_name, 255),
    media_duration_ms = v_duration,
    media_url = left(v_url, 2048),
    media_updated_at = now()
  where id = p_room_id
  returning * into v_room;

  return v_room;
end $$;

-- 9. request_upload_slot (service_role only)
create or replace function public.request_upload_slot(
  p_room_id uuid,
  p_user_id uuid,
  p_file_size bigint,
  p_r2_key text,
  p_upload_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_room public.rooms;
  v_profile public.profiles;
  v_settings jsonb;
  v_enabled boolean;
  v_free_max bigint;
  v_premium_max bigint;
  v_tier text;
  v_limits public.tier_limits;
  v_weekly_limit bigint;
begin
  if p_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null or not public.is_room_live(p_room_id) then
    raise exception 'room_ended';
  end if;

  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_user_id and role = 'host'
  ) then
    raise exception 'not_host';
  end if;

  if v_room.media_kind != 'local' or v_room.media_name is null then
    raise exception 'invalid_media';
  end if;

  select value into v_settings from public.app_settings where key = 'media_sharing';
  v_enabled := coalesce((v_settings->>'enabled')::boolean, true);
  if not v_enabled then
    raise exception 'media_sharing_disabled';
  end if;

  v_free_max := coalesce((v_settings->>'free_tier_max_file_bytes')::bigint, 2147483648);
  v_premium_max := coalesce((v_settings->>'premium_max_file_bytes')::bigint, 10737418240);

  v_tier := public.effective_tier(p_user_id);
  select * into v_limits from public.tier_limits where tier = v_tier;

  if v_limits.media_sharing = 'none' then
    raise exception 'media_sharing_disabled';
  end if;

  if p_file_size is null or p_file_size <= 0 then
    raise exception 'invalid_file_size';
  end if;

  if v_limits.media_sharing = 'limited' and p_file_size > v_free_max then
    raise exception 'upload_quota_exceeded';
  elsif v_limits.media_sharing = 'full' and p_file_size > v_premium_max then
    raise exception 'upload_quota_exceeded';
  end if;

  -- Lock profile row
  select * into v_profile from public.profiles where id = p_user_id for update;

  if v_profile.r2_cooldown_until is not null and v_profile.r2_cooldown_until > now() then
    raise exception 'upload_cooldown_active';
  end if;

  -- Multi-Factor Stale Lock Auto-Clearing
  if v_profile.active_upload_room_id is not null and v_profile.active_upload_room_id != p_room_id then
    declare
      v_prev_live boolean := public.is_room_live(v_profile.active_upload_room_id);
      v_prev_state text;
      v_prev_host boolean;
    begin
      select media_upload_state into v_prev_state from public.rooms where id = v_profile.active_upload_room_id;
      select exists(
        select 1 from public.room_members
        where room_id = v_profile.active_upload_room_id and user_id = p_user_id and role = 'host'
      ) into v_prev_host;

      if (not v_prev_live)
         or (v_prev_state is distinct from 'uploading')
         or (not v_prev_host)
         or (v_profile.active_upload_started_at < now() - interval '30 minutes') then
        update public.profiles set active_upload_room_id = null, active_upload_started_at = null where id = p_user_id;
      else
        raise exception 'active_upload_in_progress';
      end if;
    end;
  end if;

  -- Orphaned Multipart Cleanup on Same-Room Re-upload
  if v_room.media_upload_id is not null and v_room.media_upload_id != p_upload_id then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);
  end if;

  -- Weekly Quota Check for limited tier
  if v_limits.media_sharing = 'limited' then
    v_weekly_limit := v_limits.media_sharing_weekly_bytes;
    if v_profile.r2_upload_window_start < now() - interval '7 days' then
      update public.profiles
      set r2_upload_window_start = now(), r2_upload_bytes_7d = 0
      where id = p_user_id;
      v_profile.r2_upload_bytes_7d := 0;
    end if;

    if v_profile.r2_upload_bytes_7d + p_file_size > v_weekly_limit then
      raise exception 'upload_quota_exceeded';
    end if;
  end if;

  update public.profiles set
    active_upload_room_id = p_room_id,
    active_upload_started_at = now()
  where id = p_user_id;

  update public.rooms set
    media_upload_state = 'uploading',
    media_file_size = p_file_size,
    media_r2_key = p_r2_key,
    media_upload_id = p_upload_id
  where id = p_room_id;
end $$;

-- 10. record_upload_bytes (service_role only)
create or replace function public.record_upload_bytes(p_user_id uuid, p_bytes bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  if p_bytes is null or p_bytes <= 0 then
    return;
  end if;

  select * into v_profile from public.profiles where id = p_user_id for update;
  if v_profile.id is null then
    return;
  end if;

  if v_profile.r2_upload_window_start < now() - interval '7 days' then
    update public.profiles set
      r2_upload_window_start = now(),
      r2_upload_bytes_7d = p_bytes
    where id = p_user_id;
  else
    update public.profiles set
      r2_upload_bytes_7d = r2_upload_bytes_7d + p_bytes
    where id = p_user_id;
  end if;
end $$;

-- 11. set_media_upload_state (service_role only)
create or replace function public.set_media_upload_state(
  p_room_id uuid,
  p_user_id uuid,
  p_state text,
  p_file_size bigint default null,
  p_r2_key text default null,
  p_bytes_uploaded bigint default 0)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_room public.rooms;
  v_profile public.profiles;
  v_aborts int;
  v_cooldown_mins int;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then
    return;
  end if;

  if p_state not in ('none', 'uploading', 'ready', 'failed') then
    raise exception 'invalid_state';
  end if;

  if p_state = 'ready' then
    update public.rooms set
      media_upload_state = 'ready',
      media_upload_id = null,
      media_file_size = coalesce(p_file_size, media_file_size),
      media_r2_key = coalesce(p_r2_key, media_r2_key)
    where id = p_room_id;

    update public.profiles set
      active_upload_room_id = null,
      active_upload_started_at = null,
      r2_consecutive_aborts = 0
    where id = p_user_id;

    if v_room.media_sharing_level = 'limited' and p_file_size is not null then
      perform public.record_upload_bytes(p_user_id, p_file_size);
    end if;

  elsif p_state = 'failed' then
    update public.rooms set
      media_upload_state = 'failed',
      media_upload_id = null
    where id = p_room_id;

    select * into v_profile from public.profiles where id = p_user_id for update;
    if v_profile.id is not null then
      v_aborts := v_profile.r2_consecutive_aborts;
      if coalesce(p_bytes_uploaded, 0) > 52428800 then -- > 50 MB
        v_aborts := v_aborts + 1;
        v_cooldown_mins := case v_aborts
          when 1 then 1
          when 2 then 5
          else 15
        end;
        update public.profiles set
          active_upload_room_id = null,
          active_upload_started_at = null,
          r2_consecutive_aborts = v_aborts,
          r2_cooldown_until = now() + make_interval(mins => v_cooldown_mins)
        where id = p_user_id;
      else
        update public.profiles set
          active_upload_room_id = null,
          active_upload_started_at = null
        where id = p_user_id;
      end if;
    end if;

    if coalesce(p_r2_key, v_room.media_r2_key) is not null or v_room.media_upload_id is not null then
      insert into public.pending_r2_deletions (r2_key, upload_id)
      values (coalesce(p_r2_key, v_room.media_r2_key), v_room.media_upload_id);
    end if;
  else
    update public.rooms set
      media_upload_state = p_state,
      media_file_size = coalesce(p_file_size, media_file_size),
      media_r2_key = coalesce(p_r2_key, media_r2_key)
    where id = p_room_id;
  end if;
end $$;

-- 12. clear_media_sharing (host only)
create or replace function public.clear_media_sharing(
  p_room_id uuid,
  p_bytes_uploaded bigint default 0)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
  v_uploader_profile public.profiles;
  v_aborts int;
  v_cooldown_mins int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = v_uid and role = 'host'
  ) then
    raise exception 'not_host';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then
    return;
  end if;

  -- Clear upload lock on any profile holding this room
  for v_uploader_profile in
    select * from public.profiles where active_upload_room_id = p_room_id for update
  loop
    if v_room.media_upload_state = 'uploading' and coalesce(p_bytes_uploaded, 0) > 52428800 then
      v_aborts := v_uploader_profile.r2_consecutive_aborts + 1;
      v_cooldown_mins := case v_aborts
        when 1 then 1
        when 2 then 5
        else 15
      end;
      update public.profiles set
        active_upload_room_id = null,
        active_upload_started_at = null,
        r2_consecutive_aborts = v_aborts,
        r2_cooldown_until = now() + make_interval(mins => v_cooldown_mins)
      where id = v_uploader_profile.id;
    else
      update public.profiles set
        active_upload_room_id = null,
        active_upload_started_at = null
      where id = v_uploader_profile.id;
    end if;
  end loop;

  if v_room.media_r2_key is not null or v_room.media_upload_id is not null then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);
  end if;

  update public.rooms set
    media_r2_key = null,
    media_upload_id = null,
    media_file_size = null,
    media_upload_state = 'none'
  where id = p_room_id;
end $$;

-- 13. Update retire_room
create or replace function public.retire_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_room public.rooms;
begin
  update public.rooms r set
    ended_at = coalesce(r.ended_at, now()),
    resumable_until = case
      when r.persistent then null
      when r.dormant_hours > 0
        then greatest(r.expires_at, now()) + make_interval(hours => r.dormant_hours)
      else null
    end
  where r.id = p_room_id
  returning * into v_room;

  if v_room.id is null then
    return;
  end if;

  -- Clean up active R2 objects or incomplete multipart uploads
  if v_room.media_r2_key is not null or v_room.media_upload_id is not null then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);

    -- Clear R2 state on rooms so dormant/persistent rooms do not reference purged files
    update public.rooms set
      media_r2_key = null,
      media_upload_id = null,
      media_file_size = null,
      media_upload_state = 'none'
    where id = p_room_id;
  end if;

  -- Clear upload locks
  update public.profiles set
    active_upload_room_id = null,
    active_upload_started_at = null
  where active_upload_room_id = p_room_id;

  delete from public.messages where room_id = p_room_id;

  if not v_room.persistent and v_room.resumable_until is null then
    delete from public.rooms where id = p_room_id;
  end if;
end $$;

-- 14. Grants and Permissions
revoke execute on function
  public.request_upload_slot(uuid, uuid, bigint, text, text),
  public.set_media_upload_state(uuid, uuid, text, bigint, text, bigint),
  public.record_upload_bytes(uuid, bigint)
from public, anon, authenticated;

grant execute on function
  public.request_upload_slot(uuid, uuid, bigint, text, text),
  public.set_media_upload_state(uuid, uuid, text, bigint, text, bigint),
  public.record_upload_bytes(uuid, bigint)
to service_role;

revoke execute on function
  public.clear_media_sharing(uuid, bigint)
from public, anon;

grant execute on function
  public.clear_media_sharing(uuid, bigint)
to authenticated;

-- Service role table grants for Edge Functions
grant all on public.rooms to service_role;
grant all on public.room_members to service_role;
grant all on public.profiles to service_role;
grant all on public.messages to service_role;
grant all on public.pending_r2_deletions to service_role;
grant all on public.app_settings to service_role;
