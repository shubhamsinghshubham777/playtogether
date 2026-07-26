-- Readiness gate, part 2: host can remove a member, optionally barring rejoin.
-- Strict lockstep has no "start anyway" override, so kick is the only escape
-- hatch when someone can't or won't load the canonical media.
-- Living doc: docs/readiness-gate.md (§3 A2, decision D9).

-- ---------------------------------------------------------------------------
-- Bans (per room, lasts as long as the room — rooms are never deleted, only
-- ended, and joining a dead room already fails with room_ended)
-- ---------------------------------------------------------------------------

create table public.room_bans (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

-- Cascades keep the existing sweeps honest: room deletion and the daily stale-
-- guest purge (which deletes auth.users -> profiles) both clear bans, so
-- delete_account cannot start failing on a new FK the way rooms.created_by did.
-- Two layers, because a ban list is the one table where a leak is a real
-- privacy problem: RLS with deliberately no policies (a ban is never read by
-- the client — it surfaces only as join_room's error, and both RPCs below are
-- security definer), plus an explicit revoke so the platform's default grants
-- on new public tables can't quietly expose it.
alter table public.room_bans enable row level security;
revoke all on public.room_bans from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Kick
-- ---------------------------------------------------------------------------

create or replace function public.kick_member(
  p_room_id uuid,
  p_target_user_id uuid,
  p_ban boolean default false)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_target_role text;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_target_user_id is null then
    raise exception 'invalid_target';
  end if;
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = v_uid and role = 'host') then
    raise exception 'not_host';
  end if;
  if not public.is_room_live(p_room_id) then
    raise exception 'room_ended';
  end if;
  if p_target_user_id = v_uid then
    raise exception 'cannot_kick_self';
  end if;

  select role into v_target_role from public.room_members
    where room_id = p_room_id and user_id = p_target_user_id;
  if v_target_role = 'host' then
    raise exception 'cannot_kick_host';   -- unreachable while rooms have one host
  end if;

  -- Tolerant of a target who just left on their own: the ban is the part that
  -- still matters (it is what stops the rejoin), so record it either way. No
  -- host succession to run here — the host can never be the target.
  delete from public.room_members
    where room_id = p_room_id and user_id = p_target_user_id;

  if coalesce(p_ban, false) then
    insert into public.room_bans (room_id, user_id)
    values (p_room_id, p_target_user_id)
    on conflict (room_id, user_id) do nothing;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- join_room: unchanged except the ban gate (checked before the "already a
-- member" early return, so a ban can never be walked around)
-- ---------------------------------------------------------------------------

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

  if exists (select 1 from public.room_bans
             where room_id = v_room.id and user_id = v_uid) then
    raise exception 'room_banned';
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

revoke execute on function public.kick_member(uuid, uuid, boolean) from public, anon;
grant execute on function public.kick_member(uuid, uuid, boolean) to authenticated;
