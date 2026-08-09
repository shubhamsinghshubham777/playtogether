create or replace function public.room_state(p_room public.rooms)
returns text
language sql stable set search_path = ''
as $$
  select case
    when p_room.ended_at is null and p_room.expires_at > now() then 'live'
    when p_room.persistent then 'dormant'
    when p_room.resumable_until is not null and p_room.resumable_until > now() then 'dormant'
    when p_room.ended_at is null and p_room.dormant_hours > 0
         and p_room.expires_at + make_interval(hours => p_room.dormant_hours) > now() then 'dormant'
    else 'expired'
  end;
$$;
