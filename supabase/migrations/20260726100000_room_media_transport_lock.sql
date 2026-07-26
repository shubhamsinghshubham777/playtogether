-- Readiness gate, part 1: room-level canonical media + transport lock.
-- Canonical media lives on the room row (not only in broadcasts) so it survives
-- host succession and reaches late joiners / reconnects by a plain refetch.
-- Living doc: docs/readiness-gate.md (§3 A1).

-- ---------------------------------------------------------------------------
-- Room columns
-- ---------------------------------------------------------------------------

alter table public.rooms
  add column media_kind text not null default 'none'
    check (media_kind in ('none', 'local', 'youtube')),
  add column media_name text                 -- local: exact basename the gate matches on
    check (char_length(media_name) between 1 and 255),
  add column media_duration_ms bigint        -- soft ±2 s warning only, never gating
    check (media_duration_ms >= 0),
  add column media_url text
    check (char_length(media_url) between 1 and 2048),
  add column media_updated_at timestamptz,   -- ordering: lets a client drop a refetch
                                             -- that resolved after a newer broadcast
  add column transport_lock boolean not null default false;

-- Shape invariant: fields a kind doesn't carry stay null, so a stale local file
-- name can never leak into YouTube-mode gate copy.
alter table public.rooms
  add constraint rooms_media_shape_chk check (
    case media_kind
      when 'none' then media_name is null and media_duration_ms is null and media_url is null
      when 'local' then media_name is not null and media_url is null
      when 'youtube' then media_url is not null
      else false
    end
  );

-- No update policy on public.rooms exists (and none is added): members read the
-- row via "members can read their rooms", and only these security-definer RPCs
-- may write it — host-only source selection is server-enforced, not UI-enforced.

-- ---------------------------------------------------------------------------
-- RPCs (host only, live rooms only)
-- ---------------------------------------------------------------------------

create or replace function public.set_room_media(
  p_room_id uuid,
  p_kind text,
  p_name text default null,
  p_duration_ms bigint default null,
  p_url text default null)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_url text := nullif(trim(coalesce(p_url, '')), '');
  v_duration bigint := case when p_duration_ms >= 0 then p_duration_ms end;
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = v_uid and role = 'host') then
    raise exception 'not_host';
  end if;
  if not public.is_room_live(p_room_id) then
    raise exception 'room_ended';
  end if;

  if v_kind not in ('none', 'local', 'youtube')
     or (v_kind = 'local' and v_name is null)
     or (v_kind = 'youtube' and v_url is null) then
    raise exception 'invalid_media';
  end if;

  -- Normalize to the shape constraint before writing.
  if v_kind = 'none' then
    v_name := null;
    v_url := null;
    v_duration := null;
  elsif v_kind = 'local' then
    v_url := null;
  end if;

  update public.rooms set
    media_kind = v_kind,
    media_name = left(v_name, 255),
    media_duration_ms = v_duration,
    media_url = left(v_url, 2048),
    media_updated_at = now()
  where id = p_room_id
  returning * into v_room;

  return v_room;
end $$;

create or replace function public.set_transport_lock(p_room_id uuid, p_locked boolean)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from public.room_members
                 where room_id = p_room_id and user_id = v_uid and role = 'host') then
    raise exception 'not_host';
  end if;
  if not public.is_room_live(p_room_id) then
    raise exception 'room_ended';
  end if;

  update public.rooms set transport_lock = coalesce(p_locked, false)
  where id = p_room_id
  returning * into v_room;

  return v_room;
end $$;

revoke execute on function
  public.set_room_media(uuid, text, text, bigint, text),
  public.set_transport_lock(uuid, boolean)
from public, anon;

grant execute on function
  public.set_room_media(uuid, text, text, bigint, text),
  public.set_transport_lock(uuid, boolean)
to authenticated;
