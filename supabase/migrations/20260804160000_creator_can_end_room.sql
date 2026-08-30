create or replace function public.end_room(p_room_id uuid)
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
                 where room_id = p_room_id and user_id = v_uid and role = 'host')
     and not exists (select 1 from public.rooms
                     where id = p_room_id and created_by = v_uid) then
    raise exception 'not_host';
  end if;
  if not exists (select 1 from public.rooms
                 where id = p_room_id and ended_at is null) then
    return;
  end if;
  perform public.retire_room(p_room_id);
end $$;
