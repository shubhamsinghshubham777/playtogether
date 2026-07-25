-- PlayTogether multi-participant upgrade: profiles, rooms, membership, chat,
-- RLS, RPCs, realtime authorization, avatars bucket, expiry sweep.
-- Plan: docs/multi-participant-plan.md (§2 Phase 0).

create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,                         -- read-only mirror, never user-editable; null for guests
  is_guest boolean not null default false,
  display_name text not null check (char_length(display_name) between 1 and 40),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,          -- 6-char human join code, generated server-side
  name text not null default 'Watch party',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  duration_minutes int not null check (duration_minutes between 5 and 240),
  expires_at timestamptz not null,    -- created_at + duration_minutes, set by RPC
  ended_at timestamptz                -- set on expiry sweep or host "end room"
);

create table public.room_members (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('host', 'member')),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

-- Chat persistence: history lives exactly as long as the room.
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  content text not null check (char_length(content) between 1 and 500),
  created_at timestamptz not null default now()
);

create index messages_room_created_idx on public.messages (room_id, created_at);
create index room_members_user_idx on public.room_members (user_id);

-- ---------------------------------------------------------------------------
-- Profile bootstrap triggers (auth.users -> public.profiles)
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_name text;
begin
  if new.is_anonymous then
    insert into public.profiles (id, email, is_guest, display_name)
    values (new.id, null, true, 'Guest-' || lower(substr(md5(random()::text), 1, 4)));
  else
    v_name := coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Watcher');
    insert into public.profiles (id, email, is_guest, display_name, avatar_url)
    values (new.id, new.email, false, left(v_name, 40), new.raw_user_meta_data ->> 'avatar_url');
  end if;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Guest -> Google upgrade via linkIdentity, plus email changes: keep the mirror honest.
create or replace function public.handle_user_updated()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_name text;
begin
  if (old.is_anonymous and not new.is_anonymous) then
    v_name := coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''), '');
    update public.profiles
      set is_guest = false,
          email = new.email,
          display_name = case
            when display_name like 'Guest-%' and v_name <> '' then left(v_name, 40)
            else display_name end,
          updated_at = now()
      where id = new.id;
  elsif (new.email is distinct from old.email and not new.is_anonymous) then
    update public.profiles set email = new.email, updated_at = now() where id = new.id;
  end if;
  return new;
end $$;

create trigger on_auth_user_updated
  after update on auth.users
  for each row execute function public.handle_user_updated();

create or replace function public.handle_profile_touched()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger on_profile_touched
  before update on public.profiles
  for each row execute function public.handle_profile_touched();

-- ---------------------------------------------------------------------------
-- RLS helpers (security definer to avoid self-referential policy recursion)
-- ---------------------------------------------------------------------------

create or replace function public.is_room_member(p_room_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = (select auth.uid())
  );
$$;

create or replace function public.is_room_live(p_room_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.rooms
    where id = p_room_id and ended_at is null and expires_at > now()
  );
$$;

-- Safe "room:<uuid>" topic parser for realtime policies (null on garbage).
create or replace function public.room_id_from_topic(p_topic text)
returns uuid
language plpgsql immutable
as $$
begin
  if p_topic is null or p_topic not like 'room:%' then
    return null;
  end if;
  return substr(p_topic, 6)::uuid;
exception when others then
  return null;
end $$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.messages enable row level security;

create policy "profiles are readable by signed-in users"
  on public.profiles for select to authenticated
  using (true);

-- Guests cannot edit; email/id/is_guest are additionally locked by column grants below.
create policy "users update own non-guest profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id and not is_guest)
  with check ((select auth.uid()) = id and not is_guest);

revoke update on public.profiles from authenticated, anon;
grant update (display_name, avatar_url) on public.profiles to authenticated;

create policy "members can read their rooms"
  on public.rooms for select to authenticated
  using (public.is_room_member(id));

create policy "members can read the member list"
  on public.room_members for select to authenticated
  using (public.is_room_member(room_id));

create policy "members can read room chat"
  on public.messages for select to authenticated
  using (public.is_room_member(room_id));

create policy "members can post chat to live rooms"
  on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and public.is_room_member(room_id)
    and public.is_room_live(room_id)
  );

-- Realtime authorization: private channels "room:<id>", members only.
create policy "room members can receive broadcasts"
  on realtime.messages for select to authenticated
  using (
    public.room_id_from_topic(realtime.topic()) is not null
    and public.is_room_member(public.room_id_from_topic(realtime.topic()))
  );

create policy "room members can send broadcasts"
  on realtime.messages for insert to authenticated
  with check (
    public.room_id_from_topic(realtime.topic()) is not null
    and public.is_room_member(public.room_id_from_topic(realtime.topic()))
  );

-- ---------------------------------------------------------------------------
-- RPCs (security definer: caps, code generation and clocks enforced server-side)
-- ---------------------------------------------------------------------------

create or replace function public.create_room(p_name text, p_duration_minutes int)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_guest boolean;
  v_code text;
  v_room public.rooms;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no 0/O/1/I
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_duration_minutes is null or p_duration_minutes < 5 or p_duration_minutes > 240 then
    raise exception 'invalid_duration';
  end if;

  select is_guest into v_is_guest from public.profiles where id = v_uid;
  if v_is_guest and exists (
    select 1 from public.rooms
    where created_by = v_uid and ended_at is null and expires_at > now()
  ) then
    raise exception 'guest_room_limit';
  end if;

  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
      into v_code from generate_series(1, 6);
    exit when not exists (select 1 from public.rooms where code = v_code);
  end loop;

  insert into public.rooms (code, name, created_by, duration_minutes, expires_at)
  values (
    v_code,
    coalesce(nullif(trim(p_name), ''), 'Watch party'),
    v_uid,
    p_duration_minutes,
    now() + make_interval(mins => p_duration_minutes))
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
  if v_room.ended_at is not null or v_room.expires_at <= now() then
    raise exception 'room_ended';
  end if;

  if exists (select 1 from public.room_members
             where room_id = v_room.id and user_id = v_uid) then
    return v_room; -- already a member: rejoining is fine
  end if;

  select count(*) into v_count from public.room_members where room_id = v_room.id;
  if v_count >= 8 then
    raise exception 'room_full';
  end if;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'member');

  return v_room;
end $$;

create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_next uuid;
begin
  delete from public.room_members
    where room_id = p_room_id and user_id = v_uid
    returning role into v_role;

  -- Host succession: promote the earliest-joined remaining member.
  if v_role = 'host' then
    select user_id into v_next from public.room_members
      where room_id = p_room_id
      order by joined_at asc limit 1;
    if v_next is not null then
      update public.room_members set role = 'host'
        where room_id = p_room_id and user_id = v_next;
    end if;
  end if;
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
  update public.rooms set ended_at = now()
    where id = p_room_id and ended_at is null;
end $$;

create or replace function public.get_server_time()
returns timestamptz
language sql stable
as $$ select now(); $$;

create or replace function public.delete_account()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from auth.users where id = auth.uid();
end $$;

revoke execute on function
  public.create_room(text, int),
  public.join_room(text),
  public.leave_room(uuid),
  public.end_room(uuid),
  public.get_server_time(),
  public.delete_account(),
  public.is_room_member(uuid),
  public.is_room_live(uuid)
from public, anon;

grant execute on function
  public.create_room(text, int),
  public.join_room(text),
  public.leave_room(uuid),
  public.end_room(uuid),
  public.get_server_time(),
  public.delete_account(),
  public.is_room_member(uuid),
  public.is_room_live(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- Avatars bucket: public read, owners write avatars/<uid>.jpg, ~2 MB cap
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

create policy "avatar images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "users manage their own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and name = (select auth.uid())::text || '.jpg'
    and not exists (select 1 from public.profiles
                    where id = (select auth.uid()) and is_guest)
  );

create policy "users replace their own avatar"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and name = (select auth.uid())::text || '.jpg')
  with check (bucket_id = 'avatars' and name = (select auth.uid())::text || '.jpg');

create policy "users delete their own avatar"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and name = (select auth.uid())::text || '.jpg');

-- ---------------------------------------------------------------------------
-- Expiry sweep: server truth for room lifetime (every minute)
-- ---------------------------------------------------------------------------

select cron.schedule(
  'expire-rooms',
  '* * * * *',
  $$ update public.rooms set ended_at = now()
     where ended_at is null and expires_at <= now(); $$
);
