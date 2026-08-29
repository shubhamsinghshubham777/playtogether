-- Staged Media Uploads (Pre-uploading media in Lobby before room creation)

-- 1. Table schema
create table if not exists public.staged_media_uploads (
  id uuid default gen_random_uuid() primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  file_name text not null check (char_length(file_name) between 1 and 255),
  file_size bigint not null check (file_size > 0),
  duration_ms bigint check (duration_ms is null or duration_ms > 0),
  r2_key text not null check (char_length(r2_key) between 1 and 512),
  upload_id text check (upload_id is null or char_length(upload_id) between 1 and 512),
  upload_state text not null check (upload_state in ('uploading', 'ready', 'failed')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 hour'),
  claimed_room_id uuid references public.rooms(id) on delete set null
);

create index if not exists idx_staged_media_user on public.staged_media_uploads(user_id) where claimed_room_id is null;
create index if not exists idx_staged_media_expires on public.staged_media_uploads(expires_at) where claimed_room_id is null;

alter table public.staged_media_uploads enable row level security;
revoke all on public.staged_media_uploads from public, anon;
grant select, insert, update, delete on public.staged_media_uploads to authenticated;
grant all on public.staged_media_uploads to service_role;

create policy staged_media_select_own on public.staged_media_uploads
  for select to authenticated using (user_id = auth.uid());

create policy staged_media_update_own on public.staged_media_uploads
  for update to authenticated using (user_id = auth.uid());

create policy staged_media_delete_own on public.staged_media_uploads
  for delete to authenticated using (user_id = auth.uid());

-- 2. Schema changes on profiles for staged concurrency lock
alter table public.profiles
  add column if not exists active_upload_staged_id uuid references public.staged_media_uploads(id) on delete set null;

-- 3. RPC: request_staged_upload_slot
create or replace function public.request_staged_upload_slot(
  p_user_id uuid,
  p_file_size bigint,
  p_file_name text,
  p_duration_ms bigint default null,
  p_r2_key text default null,
  p_upload_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_settings jsonb;
  v_tier text;
  v_limits public.tier_limits%rowtype;
  v_profile public.profiles%rowtype;
  v_max_bytes bigint;
  v_current_usage bigint;
  v_staged_id uuid;
  v_key text;
begin
  -- 1. Global kill-switch check
  select value into v_settings from public.app_settings where key = 'media_sharing';
  if v_settings is null or not coalesce((v_settings->>'enabled')::boolean, true) then
    return jsonb_build_object('allowed', false, 'error', 'feature_disabled');
  end if;

  -- 2. Caller profile and tier
  select * into v_profile from public.profiles where id = p_user_id;
  if v_profile.id is null then
    return jsonb_build_object('allowed', false, 'error', 'user_not_found');
  end if;

  v_tier := public.effective_tier(p_user_id);
  select * into v_limits from public.tier_limits where tier = v_tier;

  -- 3. Entitlement check
  if v_limits.media_sharing = 'none' then
    return jsonb_build_object('allowed', false, 'error', 'tier_unauthorized');
  end if;

  -- 4. Abort penalty cooldown check
  if v_profile.r2_cooldown_until is not null and v_profile.r2_cooldown_until > now() then
    return jsonb_build_object(
      'allowed', false,
      'error', 'cooldown_active',
      'cooldown_until', v_profile.r2_cooldown_until
    );
  end if;

  -- 5. File size limits
  if v_tier = 'free' then
    v_max_bytes := coalesce((v_settings->>'free_tier_max_file_bytes')::bigint, 2147483648); -- 2 GB
  else
    v_max_bytes := coalesce((v_settings->>'premium_max_file_bytes')::bigint, 10737418240); -- 10 GB
  end if;

  if p_file_size > v_max_bytes then
    return jsonb_build_object(
      'allowed', false,
      'error', 'file_too_large',
      'max_bytes', v_max_bytes
    );
  end if;

  -- 6. Rolling 7-day quota check (Free tier only)
  if v_limits.media_sharing = 'limited' then
    if now() - v_profile.r2_upload_window_start > interval '7 days' then
      update public.profiles set
        r2_upload_bytes_7d = 0,
        r2_upload_window_start = now()
      where id = p_user_id;
      v_current_usage := 0;
    else
      v_current_usage := v_profile.r2_upload_bytes_7d;
    end if;

    if (v_current_usage + p_file_size) > v_limits.media_sharing_weekly_bytes then
      return jsonb_build_object(
        'allowed', false,
        'error', 'quota_exceeded',
        'used_bytes', v_current_usage,
        'weekly_limit', v_limits.media_sharing_weekly_bytes,
        'resets_at', v_profile.r2_upload_window_start + interval '7 days'
      );
    end if;
  end if;

  -- 7. Active upload lock check
  -- If previous staged upload exists for this user, automatically clear it to allow fresh retry
  if v_profile.active_upload_staged_id is not null then
    perform public.clear_staged_upload(v_profile.active_upload_staged_id, 0);
    select * into v_profile from public.profiles where id = p_user_id;
  end if;

  -- Active in-room upload lock check (1-hour lock timeout)
  if v_profile.active_upload_room_id is not null
     and (v_profile.active_upload_started_at is not null and now() - v_profile.active_upload_started_at < interval '1 hour') then
    return jsonb_build_object('allowed', false, 'error', 'concurrent_upload_active');
  end if;

  -- 8. Create staged upload record
  v_key := coalesce(p_r2_key, 'users/' || p_user_id::text || '/staged/' || gen_random_uuid()::text || '-' || p_file_name);

  insert into public.staged_media_uploads (
    user_id,
    file_name,
    file_size,
    duration_ms,
    r2_key,
    upload_id,
    upload_state,
    expires_at
  )
  values (
    p_user_id,
    p_file_name,
    p_file_size,
    p_duration_ms,
    v_key,
    p_upload_id,
    'uploading',
    now() + interval '1 hour'
  )
  returning id into v_staged_id;

  -- 9. Acquire lock on profile
  update public.profiles set
    active_upload_room_id = null,
    active_upload_staged_id = v_staged_id,
    active_upload_started_at = now()
  where id = p_user_id;

  return jsonb_build_object(
    'allowed', true,
    'staged_id', v_staged_id,
    'r2_key', v_key,
    'sharing_level', v_limits.media_sharing
  );
end $$;

-- 4. RPC: set_staged_upload_state
create or replace function public.set_staged_upload_state(
  p_staged_id uuid,
  p_user_id uuid,
  p_state text,
  p_file_size bigint default null,
  p_r2_key text default null,
  p_bytes_uploaded bigint default 0
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_staged public.staged_media_uploads%rowtype;
begin
  select * into v_staged from public.staged_media_uploads
  where id = p_staged_id and user_id = p_user_id;

  if v_staged.id is null then
    return;
  end if;

  update public.staged_media_uploads set
    upload_state = p_state,
    upload_id = case when p_state = 'ready' then null else upload_id end,
    file_size = coalesce(p_file_size, file_size),
    r2_key = coalesce(p_r2_key, r2_key)
  where id = p_staged_id;

  -- Debit bytes on completion or abort with partial transfer
  if p_state = 'ready' then
    update public.profiles set
      r2_upload_bytes_7d = r2_upload_bytes_7d + coalesce(p_file_size, v_staged.file_size),
      r2_consecutive_aborts = 0,
      active_upload_staged_id = null,
      active_upload_started_at = null
    where id = p_user_id;
  elsif p_state = 'failed' then
    update public.profiles set
      r2_upload_bytes_7d = r2_upload_bytes_7d + p_bytes_uploaded,
      active_upload_staged_id = null,
      active_upload_started_at = null
    where id = p_user_id;
  end if;
end $$;

-- 5. RPC: clear_staged_upload
create or replace function public.clear_staged_upload(
  p_staged_id uuid,
  p_bytes_uploaded bigint default 0
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_staged public.staged_media_uploads%rowtype;
  v_new_aborts int;
  v_cooldown timestamptz := null;
begin
  select * into v_staged from public.staged_media_uploads where id = p_staged_id;
  if v_staged.id is null then
    return;
  end if;

  -- Enqueue for R2 cleanup
  if v_staged.r2_key is not null or v_staged.upload_id is not null then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_staged.r2_key, v_staged.upload_id);
  end if;

  -- Abort penalty tracking
  select coalesce(r2_consecutive_aborts, 0) + 1 into v_new_aborts
  from public.profiles where id = v_staged.user_id;

  if v_new_aborts >= 5 then
    v_cooldown := now() + interval '30 minutes';
  end if;

  update public.profiles set
    r2_upload_bytes_7d = r2_upload_bytes_7d + p_bytes_uploaded,
    r2_consecutive_aborts = v_new_aborts,
    r2_cooldown_until = coalesce(v_cooldown, r2_cooldown_until),
    active_upload_staged_id = null,
    active_upload_started_at = null
  where id = v_staged.user_id;

  delete from public.staged_media_uploads where id = p_staged_id;
end $$;

-- 6. Update create_room() to accept optional p_staged_id
drop function if exists public.create_room(text, int);
drop function if exists public.create_room(text, int, uuid);

create or replace function public.create_room(
  p_name text,
  p_duration_minutes int,
  p_staged_id uuid default null
)
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
  v_staged public.staged_media_uploads%rowtype;
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

  -- If staged media provided, validate ownership and ready status
  if p_staged_id is not null then
    select * into v_staged from public.staged_media_uploads
    where id = p_staged_id
      and user_id = v_uid
      and upload_state = 'ready'
      and claimed_room_id is null
      and expires_at > now();

    if v_staged.id is null then
      raise exception 'staged_media_invalid';
    end if;
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
    code,
    name,
    created_by,
    duration_minutes,
    expires_at,
    persistent,
    dormant_hours,
    av_level,
    max_members,
    media_kind,
    media_name,
    media_duration_ms,
    media_file_size,
    media_r2_key,
    media_upload_state,
    media_sharing_level,
    media_updated_at
  )
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
    case when p_staged_id is not null then 'local' else 'none' end,
    case when p_staged_id is not null then v_staged.file_name else null end,
    case when p_staged_id is not null then v_staged.duration_ms else null end,
    case when p_staged_id is not null then v_staged.file_size else null end,
    case when p_staged_id is not null then v_staged.r2_key else null end,
    case when p_staged_id is not null then 'ready' else 'none' end,
    v_limits.media_sharing,
    case when p_staged_id is not null then now() else null end
  )
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host');

  -- Mark staged upload as claimed
  if p_staged_id is not null then
    update public.staged_media_uploads
    set claimed_room_id = v_room.id
    where id = p_staged_id;
  end if;

  return v_room;
end $$;

-- 7. Grants
grant execute on function public.request_staged_upload_slot to service_role;
grant execute on function public.set_staged_upload_state to service_role;
grant execute on function public.clear_staged_upload to service_role;
grant execute on function public.create_room(text, int, uuid) to authenticated;
