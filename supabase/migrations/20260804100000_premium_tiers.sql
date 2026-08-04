create table public.tier_limits (
  tier text primary key check (tier in ('guest', 'free', 'premium')),
  max_live_rooms int not null check (max_live_rooms > 0),
  max_members int not null check (max_members between 1 and 64),
  max_session_minutes int not null check (max_session_minutes between 5 and 1440),
  max_total_session_minutes int not null check (max_total_session_minutes between 5 and 1440),
  av_level text not null check (av_level in ('none', 'voice', 'video')),
  persistent_room_cap int not null default 0 check (persistent_room_cap >= 0),
  dormant_hours int not null default 0 check (dormant_hours >= 0),
  free_extension_minutes int not null default 0 check (free_extension_minutes >= 0),
  constraint tier_limits_total_covers_session_chk
    check (max_total_session_minutes >= max_session_minutes)
);

insert into public.tier_limits (
  tier, max_live_rooms, max_members, max_session_minutes, max_total_session_minutes,
  av_level, persistent_room_cap, dormant_hours, free_extension_minutes)
values
  ('guest',   1,  4,  60,   60, 'none',  0,  0,  0),
  ('free',    4,  8, 240,  240, 'voice', 0, 24, 60),
  ('premium', 20, 16, 240, 1440, 'video', 20, 24, 0);

create table public.subscriptions (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  tier text not null check (tier in ('free', 'premium')),
  current_period_end timestamptz,
  source text not null default 'manual',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.tier_limits enable row level security;
alter table public.subscriptions enable row level security;

create policy "tier limits are readable by signed-in users"
  on public.tier_limits for select to authenticated
  using (true);

create policy "users read their own subscription"
  on public.subscriptions for select to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete on public.tier_limits from anon, authenticated;
revoke insert, update, delete on public.subscriptions from anon, authenticated;

create or replace function public.effective_tier(p_user_id uuid default auth.uid())
returns text
language sql stable security definer set search_path = ''
as $$
  select case
    when p_user_id is null then 'guest'
    when coalesce((select is_guest from public.profiles where id = p_user_id), false) then 'guest'
    when exists (
      select 1 from public.subscriptions s
      where s.user_id = p_user_id
        and s.tier = 'premium'
        and (s.current_period_end is null or s.current_period_end > now())
    ) then 'premium'
    else 'free'
  end;
$$;

create or replace function public.my_entitlement()
returns public.tier_limits
language sql stable security definer set search_path = ''
as $$
  select l.* from public.tier_limits l where l.tier = public.effective_tier(auth.uid());
$$;

alter table public.rooms
  add column persistent boolean not null default false,
  add column resumable_until timestamptz,
  add column dormant_hours int not null default 24 check (dormant_hours >= 0),
  add column av_level text not null default 'voice'
    check (av_level in ('none', 'voice', 'video')),
  add column max_members int not null default 8 check (max_members between 1 and 64),
  add column media_position_ms bigint check (media_position_ms >= 0),
  add column media_position_at timestamptz;

alter table public.rooms
  drop constraint rooms_duration_minutes_check,
  add constraint rooms_duration_minutes_chk check (duration_minutes between 5 and 1440);

alter table public.profiles
  add column free_extension_used boolean not null default false;

create index rooms_created_by_idx on public.rooms (created_by);

create or replace function public.clear_media_position()
returns trigger
language plpgsql
as $$
begin
  if new.media_updated_at is distinct from old.media_updated_at then
    new.media_position_ms := null;
    new.media_position_at := null;
  end if;
  return new;
end $$;

create trigger on_room_media_changed
  before update on public.rooms
  for each row execute function public.clear_media_position();

create or replace function public.room_state(p_room public.rooms)
returns text
language sql stable set search_path = ''
as $$
  select case
    when p_room.ended_at is null and p_room.expires_at > now() then 'live'
    when p_room.persistent then 'dormant'
    when p_room.resumable_until is not null and p_room.resumable_until > now() then 'dormant'
    else 'expired'
  end;
$$;

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

  delete from public.messages where room_id = p_room_id;

  if not v_room.persistent and v_room.resumable_until is null then
    delete from public.rooms where id = p_room_id;
  end if;
end $$;

create or replace function public.sweep_rooms()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select id from public.rooms where ended_at is null and expires_at <= now()
  loop
    perform public.retire_room(v_id);
  end loop;

  update public.rooms r set
    persistent = false,
    resumable_until = now() + interval '7 days'
  where r.persistent
    and r.ended_at is not null
    and public.effective_tier(r.created_by) <> 'premium';

  delete from public.rooms r
  where r.ended_at is not null
    and not r.persistent
    and (r.resumable_until is null or r.resumable_until <= now());
end $$;

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
    persistent, dormant_hours, av_level, max_members)
  values (
    v_code,
    coalesce(nullif(left(trim(p_name), 60), ''), 'Watch party'),
    v_uid,
    p_duration_minutes,
    now() + make_interval(mins => p_duration_minutes),
    v_limits.persistent_room_cap > 0,
    v_limits.dormant_hours,
    v_limits.av_level,
    v_limits.max_members)
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host');

  return v_room;
end $$;

create or replace function public.join_room(p_code text)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
  v_count int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_room from public.rooms where code = upper(trim(p_code));
  if not found then
    raise exception 'room_not_found';
  end if;

  if exists (select 1 from public.room_bans
             where room_id = v_room.id and user_id = v_uid) then
    raise exception 'room_banned';
  end if;

  if public.room_state(v_room) = 'dormant' then
    raise exception 'room_dormant';
  end if;
  if public.room_state(v_room) <> 'live' then
    raise exception 'room_ended';
  end if;

  if exists (select 1 from public.room_members
             where room_id = v_room.id and user_id = v_uid) then
    return v_room;
  end if;

  select count(*) into v_count from public.room_members where room_id = v_room.id;
  if v_count >= v_room.max_members then
    raise exception 'room_full';
  end if;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'member');

  return v_room;
end $$;

create or replace function public.end_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = v_uid and role = 'host') then
    raise exception 'not_host';
  end if;
  if not exists (select 1 from public.rooms
                 where id = p_room_id and ended_at is null) then
    return;
  end if;
  perform public.retire_room(p_room_id);
end $$;

create or replace function public.extend_room(p_room_id uuid, p_minutes int)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tier text;
  v_limits public.tier_limits;
  v_room public.rooms;
  v_minutes int;
  v_one_off boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = v_uid and role = 'host') then
    raise exception 'not_host';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found or public.room_state(v_room) <> 'live' then
    raise exception 'room_ended';
  end if;

  v_tier := public.effective_tier(v_uid);
  select * into v_limits from public.tier_limits where tier = v_tier;

  if v_limits.max_total_session_minutes > v_limits.max_session_minutes then
    v_one_off := false;
    v_minutes := coalesce(p_minutes, 0);
    if v_minutes < 5 then
      raise exception 'invalid_duration';
    end if;
  elsif v_limits.free_extension_minutes > 0 then
    v_one_off := true;
    if (select free_extension_used from public.profiles where id = v_uid) then
      raise exception 'extension_used';
    end if;
    v_minutes := v_limits.free_extension_minutes;
  else
    raise exception 'extend_not_allowed';
  end if;

  if v_room.duration_minutes + v_minutes > v_limits.max_total_session_minutes then
    raise exception 'extension_cap';
  end if;

  update public.rooms set
    duration_minutes = duration_minutes + v_minutes,
    expires_at = expires_at + make_interval(mins => v_minutes)
  where id = p_room_id
  returning * into v_room;

  if v_one_off then
    update public.profiles set free_extension_used = true where id = v_uid;
  end if;

  return v_room;
end $$;

create or replace function public.resume_room(p_room_id uuid, p_minutes int)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_limits public.tier_limits;
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = v_uid and role = 'host') then
    raise exception 'not_host';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'room_not_found';
  end if;
  if public.room_state(v_room) = 'live' then
    return v_room;
  end if;
  if public.room_state(v_room) <> 'dormant' then
    raise exception 'room_ended';
  end if;

  select * into v_limits from public.tier_limits
    where tier = public.effective_tier(v_uid);
  if p_minutes is null or p_minutes < 5 or p_minutes > v_limits.max_session_minutes then
    raise exception 'invalid_duration';
  end if;

  update public.rooms set
    ended_at = null,
    resumable_until = null,
    duration_minutes = p_minutes,
    expires_at = now() + make_interval(mins => p_minutes),
    max_members = v_limits.max_members,
    av_level = v_limits.av_level,
    dormant_hours = v_limits.dormant_hours,
    persistent = v_limits.persistent_room_cap > 0
  where id = p_room_id
  returning * into v_room;

  return v_room;
end $$;

create or replace function public.delete_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = v_uid and role = 'host'
  ) and not exists (
    select 1 from public.rooms where id = p_room_id and created_by = v_uid
  ) then
    raise exception 'not_host';
  end if;
  delete from public.rooms where id = p_room_id;
end $$;

create or replace function public.update_media_position(p_room_id uuid, p_position_ms bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = v_uid) then
    raise exception 'not_a_member';
  end if;
  if not public.is_room_live(p_room_id) then
    raise exception 'room_ended';
  end if;
  if p_position_ms is null or p_position_ms < 0 then
    raise exception 'invalid_position';
  end if;

  update public.rooms set
    media_position_ms = p_position_ms,
    media_position_at = now()
  where id = p_room_id;
end $$;

create or replace function public.list_my_rooms()
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
  state text,
  role text,
  member_count int
)
language sql stable security definer set search_path = ''
as $$
  select
    r.id, r.code, r.name, r.created_by, r.created_at, r.duration_minutes,
    r.expires_at, r.ended_at, r.resumable_until, r.persistent, r.dormant_hours,
    r.av_level, r.max_members, r.transport_lock,
    r.media_kind, r.media_name, r.media_duration_ms, r.media_url, r.media_updated_at,
    r.media_position_ms, r.media_position_at,
    public.room_state(r),
    m.role,
    (select count(*)::int from public.room_members x where x.room_id = r.id)
  from public.rooms r
  join public.room_members m on m.room_id = r.id and m.user_id = auth.uid()
  where auth.uid() is not null
    and public.room_state(r) in ('live', 'dormant')
  order by (public.room_state(r) = 'live') desc, r.expires_at desc;
$$;

revoke execute on function
  public.effective_tier(uuid),
  public.my_entitlement(),
  public.room_state(public.rooms),
  public.retire_room(uuid),
  public.sweep_rooms(),
  public.extend_room(uuid, int),
  public.resume_room(uuid, int),
  public.delete_room(uuid),
  public.update_media_position(uuid, bigint),
  public.list_my_rooms()
from public, anon;

grant execute on function
  public.effective_tier(uuid),
  public.my_entitlement(),
  public.room_state(public.rooms),
  public.extend_room(uuid, int),
  public.resume_room(uuid, int),
  public.delete_room(uuid),
  public.update_media_position(uuid, bigint),
  public.list_my_rooms()
to authenticated;

select cron.unschedule('expire-rooms');
select cron.unschedule('purge-ended-rooms');

select cron.schedule('sweep-rooms', '* * * * *', $$ select public.sweep_rooms(); $$);
