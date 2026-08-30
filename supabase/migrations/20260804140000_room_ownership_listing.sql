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
