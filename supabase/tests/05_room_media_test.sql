begin;
select plan(23);

create function pg_temp.mk_user() returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, false, 'u' || replace(v_id::text, '-', '') || '@example.test', '{}'::jsonb);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

create temp table t (k text primary key, v uuid);
create temp table s (k text primary key, v timestamptz);

do $$
declare v_host uuid; v_member uuid; v_room public.rooms;
begin
  v_host := pg_temp.mk_user();
  v_member := pg_temp.mk_user();
  insert into t values ('host', v_host), ('member', v_member);

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Media room', 60);
  insert into t values ('room', v_room.id);

  perform pg_temp.act_as(v_member);
  perform public.join_room(v_room.code);

  perform pg_temp.act_as(v_host);
  perform public.set_room_media(v_room.id, 'local', 'movie.mkv', 7200000);
  insert into s values ('first', (select media_updated_at from public.rooms where id = v_room.id));
end $$;

select is(
  (select media_kind from public.rooms where id = (select v from t where k = 'room')),
  'local',
  'the host can set local media');

select is(
  (select media_name from public.rooms where id = (select v from t where k = 'room')),
  'movie.mkv',
  'the basename the gate matches on is stored');

select is(
  (select media_duration_ms from public.rooms where id = (select v from t where k = 'room')),
  7200000::bigint,
  'the duration is stored');

select is(
  (select media_url from public.rooms where id = (select v from t where k = 'room')),
  null::text,
  'local media carries no url');

select isnt(
  (select media_updated_at from public.rooms where id = (select v from t where k = 'room')),
  null::timestamptz,
  'the server-clock ordering key is stamped');

do $$
begin
  update public.rooms set media_updated_at = now() - interval '1 hour'
    where id = (select v from t where k = 'room');
  perform public.set_room_media(
    (select v from t where k = 'room'), 'local', 'other.mkv', 100);
end $$;

select ok(
  (select media_updated_at from public.rooms where id = (select v from t where k = 'room'))
    > now() - interval '1 minute',
  'every set restamps media_updated_at, so clients can order a refetch against a broadcast');

do $$
begin
  perform public.set_room_media(
    (select v from t where k = 'room'), 'youtube', null, null, 'https://youtu.be/abc');
end $$;

select is(
  (select media_url from public.rooms where id = (select v from t where k = 'room')),
  'https://youtu.be/abc',
  'the host can set youtube media');

select is(
  (select media_name from public.rooms where id = (select v from t where k = 'room')),
  null::text,
  'switching to youtube clears the stale local basename');

do $$
begin
  perform public.set_room_media((select v from t where k = 'room'), 'none');
end $$;

select is(
  (select media_kind || coalesce(media_name, '-') || coalesce(media_url, '-')
     || coalesce(media_duration_ms::text, '-')
   from public.rooms where id = (select v from t where k = 'room')),
  'none---',
  'setting none clears every per-kind field');

select is(
  (select media_kind from public.set_room_media(
     (select v from t where k = 'room'), '  LOCAL  ', 'movie.mkv')),
  'local',
  'the kind is trimmed and lowercased');

select is(
  (select media_duration_ms from public.set_room_media(
     (select v from t where k = 'room'), 'local', 'movie.mkv', -5)),
  null::bigint,
  'a negative duration is dropped rather than stored');

select throws_ok(
  $$ select public.set_room_media((select v from t where k = 'room'), 'local', null) $$,
  'invalid_media',
  'local media without a basename is rejected');

select throws_ok(
  $$ select public.set_room_media((select v from t where k = 'room'), 'local', '   ') $$,
  'invalid_media',
  'a whitespace-only basename is rejected');

select throws_ok(
  $$ select public.set_room_media((select v from t where k = 'room'), 'youtube') $$,
  'invalid_media',
  'youtube media without a url is rejected');

select throws_ok(
  $$ select public.set_room_media((select v from t where k = 'room'), 'vimeo', 'x') $$,
  'invalid_media',
  'an unknown kind is rejected');

do $$ begin perform pg_temp.act_as((select v from t where k = 'member')); end $$;

select throws_ok(
  $$ select public.set_room_media((select v from t where k = 'room'), 'local', 'sneaky.mkv') $$,
  'not_host',
  'source selection is host-only, enforced on the server not in the UI');

select throws_ok(
  $$ select public.set_transport_lock((select v from t where k = 'room'), true) $$,
  'not_host',
  'the transport lock is host-only');

do $$
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.set_transport_lock((select v from t where k = 'room'), true);
end $$;

select ok(
  (select transport_lock from public.rooms where id = (select v from t where k = 'room')),
  'the host can take the remote');

select is(
  (select transport_lock from public.set_transport_lock(
     (select v from t where k = 'room'), null)),
  false,
  'a null lock reads as unlocked');

select throws_ok(
  $$ update public.rooms
       set media_kind = 'local', media_name = 'a.mkv', media_url = 'https://youtu.be/x'
     where id = (select v from t where k = 'room') $$,
  '23514',
  null,
  'the shape constraint rejects local media carrying a url');

select throws_ok(
  $$ update public.rooms
       set media_kind = 'none', media_name = 'leftover.mkv', media_url = null,
           media_duration_ms = null
     where id = (select v from t where k = 'room') $$,
  '23514',
  null,
  'the shape constraint rejects a cleared kind that kept its basename');

select throws_ok(
  $$ update public.rooms
       set media_kind = 'youtube', media_name = null, media_url = null
     where id = (select v from t where k = 'room') $$,
  '23514',
  null,
  'the shape constraint rejects youtube media with no url');

do $$
begin
  update public.rooms set ended_at = now() where id = (select v from t where k = 'room');
end $$;

select throws_ok(
  $$ select public.set_room_media((select v from t where k = 'room'), 'local', 'late.mkv') $$,
  'room_ended',
  'media cannot be set on a room that has ended');

select * from finish();
rollback;
