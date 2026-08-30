create or replace function public.announce_room_ended(p_room_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'senderId', coalesce((select auth.uid())::text, 'server'),
      'timestamp', (extract(epoch from clock_timestamp()) * 1000)::bigint,
      'reason', p_reason),
    'room_ended',
    'room:' || p_room_id::text,
    true);
exception when others then
  raise warning 'announce_room_ended failed for %: %', p_room_id, sqlerrm;
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
    select 1 from public.rooms where id = p_room_id and created_by = v_uid
  ) then
    raise exception 'not_owner';
  end if;

  perform public.announce_room_ended(p_room_id, 'deleted');
  delete from public.rooms where id = p_room_id;
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
  perform public.announce_room_ended(p_room_id, 'ended');
  perform public.retire_room(p_room_id);
end $$;

drop function if exists public.list_my_rooms();

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
  member_count int,
  is_owner boolean
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
    (select count(*)::int from public.room_members x where x.room_id = r.id),
    r.created_by = (select auth.uid())
  from public.rooms r
  join public.room_members m on m.room_id = r.id and m.user_id = (select auth.uid())
  where (select auth.uid()) is not null
    and public.room_state(r) in ('live', 'dormant')
  order by (public.room_state(r) = 'live') desc, r.expires_at desc;
$$;

revoke execute on function
  public.announce_room_ended(uuid, text),
  public.list_my_rooms()
from public, anon;

grant execute on function public.list_my_rooms() to authenticated;
