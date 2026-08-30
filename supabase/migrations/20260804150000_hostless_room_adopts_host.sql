create or replace function public.join_room(p_code text)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
  v_count int;
  v_has_host boolean;
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

  select exists (select 1 from public.room_members
                 where room_id = v_room.id and role = 'host') into v_has_host;

  if exists (select 1 from public.room_members
             where room_id = v_room.id and user_id = v_uid) then
    if not v_has_host then
      update public.room_members set role = 'host'
        where room_id = v_room.id and user_id = v_uid;
    end if;
    return v_room;
  end if;

  select count(*) into v_count from public.room_members where room_id = v_room.id;
  if v_count >= v_room.max_members then
    raise exception 'room_full';
  end if;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, case when v_has_host then 'member' else 'host' end);

  return v_room;
end $$;
