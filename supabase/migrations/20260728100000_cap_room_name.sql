-- Room names were the one user-supplied string with no bound on either side,
-- while profiles.display_name has carried char_length 1..40 since day one. The
-- rendering is safe already (both room headers ellipsize), so this is about the
-- row rather than the layout: create_room is reachable by any authenticated
-- client, and rooms.name is refetched by every member on entry and on every
-- resubscribe, so an unbounded value is paid for repeatedly by everyone.

-- Existing rows first, so the constraint below can be validated immediately
-- rather than left `not valid`. Rooms are short-lived (<= 4 h) and swept, so
-- this touches almost nothing in practice.
update public.rooms
set name = left(trim(name), 60)
where name <> left(trim(name), 60);

-- Belt and braces: create_room is the only writer today (public.rooms has no
-- update policy and none is planned), but the constraint is what keeps that
-- true if a rename RPC ever lands.
alter table public.rooms
  add constraint rooms_name_len_chk check (char_length(name) between 1 and 60);

-- Unchanged from the original except the name expression: trim now applies to
-- the stored value, not just the emptiness test, and the result is capped.
-- Truncation is deliberately silent — the client caps the field at the same 60,
-- so anything longer arrived from outside the UI and has no one to show copy to.
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
    coalesce(nullif(left(trim(p_name), 60), ''), 'Watch party'),
    v_uid,
    p_duration_minutes,
    now() + make_interval(mins => p_duration_minutes))
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host');

  return v_room;
end $$;
