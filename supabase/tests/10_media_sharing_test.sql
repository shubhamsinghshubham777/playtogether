begin;
select plan(25);

create function pg_temp.mk_user(p_is_anon boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, p_is_anon, 'u' || replace(v_id::text, '-', '') || '@example.test', '{}'::jsonb);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

create function pg_temp.act_as_service_role() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}'::text, true);
end $$;

create temp table t (k text primary key, v uuid);

do $$
declare
  v_host uuid;
  v_guest uuid;
  v_room public.rooms;
begin
  v_host := pg_temp.mk_user(false);
  v_guest := pg_temp.mk_user(true);
  insert into t values ('host', v_host), ('guest', v_guest);

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Host Room', 60);
  insert into t values ('room', v_room.id);
end $$;

-- 1. create_room sets media_sharing_level based on tier
select is(
  (select media_sharing_level from public.rooms where id = (select v from t where k = 'room')),
  'limited',
  'free tier host creates room with limited media sharing level');

-- 2. list_my_rooms returns media_sharing_level and media_upload_state
select is(
  (select media_sharing_level from public.list_my_rooms() where id = (select v from t where k = 'room')),
  'limited',
  'list_my_rooms includes media_sharing_level');

select is(
  (select media_upload_state from public.list_my_rooms() where id = (select v from t where k = 'room')),
  'none',
  'list_my_rooms includes media_upload_state');

-- 3. Check shape constraint
select throws_ok(
  $$ update public.rooms
     set media_kind = 'local', media_name = 'test.mp4', media_upload_state = 'ready', media_r2_key = null
     where id = (select v from t where k = 'room') $$,
  '23514',
  null,
  'shape constraint rejects ready local upload without r2_key');

select throws_ok(
  $$ update public.rooms
     set media_kind = 'local', media_name = 'test.mp4', media_upload_state = 'ready', media_r2_key = 'k', media_file_size = null
     where id = (select v from t where k = 'room') $$,
  '23514',
  null,
  'shape constraint rejects ready local upload without media_file_size');

select throws_ok(
  $$ update public.rooms
     set media_kind = 'youtube', media_url = 'https://youtu.be/123', media_upload_state = 'uploading'
     where id = (select v from t where k = 'room') $$,
  '23514',
  null,
  'shape constraint rejects youtube mode with uploading state');

-- 4. Permissions check: request_upload_slot is service_role only
select ok(
  not has_function_privilege('authenticated', 'public.request_upload_slot(uuid, uuid, bigint, text, text)', 'EXECUTE'),
  'authenticated user cannot execute request_upload_slot directly');

select ok(
  has_function_privilege('service_role', 'public.request_upload_slot(uuid, uuid, bigint, text, text)', 'EXECUTE'),
  'service_role can execute request_upload_slot');

-- 5. Set local media on room
do $$
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.set_room_media((select v from t where k = 'room'), 'local', 'movie.mp4', 5000);
end $$;

-- 6. request_upload_slot via service_role succeeds
do $$
begin
  perform pg_temp.act_as_service_role();
  perform public.request_upload_slot(
    (select v from t where k = 'room'),
    (select v from t where k = 'host'),
    104857600::bigint, -- 100 MB
    'rooms/r1/test.mp4',
    'upload_id_1'
  );
end $$;

select is(
  (select media_upload_state from public.rooms where id = (select v from t where k = 'room')),
  'uploading',
  'request_upload_slot sets media_upload_state to uploading');

select is(
  (select active_upload_room_id from public.profiles where id = (select v from t where k = 'host')),
  (select v from t where k = 'room'),
  'request_upload_slot acquires active_upload_room_id lock on host profile');

-- 7. Second upload while first is in progress in another room throws active_upload_in_progress
do $$
declare
  v_room2 public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  v_room2 := public.create_room('Host Room 2', 60);
  insert into t values ('room2', v_room2.id);
  perform public.set_room_media(v_room2.id, 'local', 'other.mp4', 5000);
end $$;

select throws_ok(
  $$ select public.request_upload_slot(
       (select v from t where k = 'room2'),
       (select v from t where k = 'host'),
       1000000::bigint,
       'rooms/r2/other.mp4',
       'upload_id_2') $$,
  'active_upload_in_progress',
  'request_upload_slot prevents concurrent active uploads across rooms');

-- 8. Same-room re-upload queues old session to pending_r2_deletions
do $$
begin
  perform pg_temp.act_as_service_role();
  perform public.request_upload_slot(
    (select v from t where k = 'room'),
    (select v from t where k = 'host'),
    209715200::bigint, -- 200 MB
    'rooms/r1/test2.mp4',
    'upload_id_2'
  );
end $$;

select is(
  (select count(*)::int from public.pending_r2_deletions where upload_id = 'upload_id_1'),
  1,
  'same-room re-upload enqueues previous upload session to pending_r2_deletions');

-- 9. Complete upload via set_media_upload_state('ready')
do $$
begin
  perform pg_temp.act_as_service_role();
  perform public.set_media_upload_state(
    (select v from t where k = 'room'),
    (select v from t where k = 'host'),
    'ready',
    209715200::bigint,
    'rooms/r1/test2.mp4',
    209715200::bigint
  );
end $$;

select is(
  (select media_upload_state from public.rooms where id = (select v from t where k = 'room')),
  'ready',
  'set_media_upload_state ready updates state');

select is(
  (select media_upload_id from public.rooms where id = (select v from t where k = 'room')),
  null::text,
  'set_media_upload_state ready clears media_upload_id');

select is(
  (select active_upload_room_id from public.profiles where id = (select v from t where k = 'host')),
  null::uuid,
  'set_media_upload_state ready clears active upload lock');

select is(
  (select r2_upload_bytes_7d from public.profiles where id = (select v from t where k = 'host')),
  209715200::bigint,
  'set_media_upload_state ready debits weekly bandwidth quota');

-- 10. set_room_media switch to youtube cleans up R2 object
do $$
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.set_room_media(
    (select v from t where k = 'room'),
    'youtube',
    null,
    null,
    'https://youtu.be/xyz'
  );
end $$;

select is(
  (select count(*)::int from public.pending_r2_deletions where r2_key = 'rooms/r1/test2.mp4'),
  1,
  'switching to youtube queues R2 key to pending_r2_deletions');

select is(
  (select media_r2_key from public.rooms where id = (select v from t where k = 'room')),
  null::text,
  'switching to youtube resets media_r2_key on room');

select is(
  (select media_upload_state from public.rooms where id = (select v from t where k = 'room')),
  'none',
  'switching to youtube resets media_upload_state to none');

-- 11. Clear media sharing via clear_media_sharing RPC
do $$
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.set_room_media((select v from t where k = 'room2'), 'local', 'movie2.mp4', 1000);
  perform pg_temp.act_as_service_role();
  perform public.request_upload_slot(
    (select v from t where k = 'room2'),
    (select v from t where k = 'host'),
    100000000::bigint,
    'rooms/r2/movie2.mp4',
    'upload_id_3'
  );
  -- Host calls clear_media_sharing with heavy abort (> 50 MB)
  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.clear_media_sharing((select v from t where k = 'room2'), 60000000::bigint);
end $$;

select is(
  (select media_upload_state from public.rooms where id = (select v from t where k = 'room2')),
  'none',
  'clear_media_sharing resets media_upload_state to none');

select is(
  (select count(*)::int from public.pending_r2_deletions where upload_id = 'upload_id_3'),
  1,
  'clear_media_sharing queues incomplete multipart upload to pending_r2_deletions');

select is(
  (select r2_consecutive_aborts from public.profiles where id = (select v from t where k = 'host')),
  1,
  'heavy abort increments r2_consecutive_aborts');

select isnt(
  (select r2_cooldown_until from public.profiles where id = (select v from t where k = 'host')),
  null::timestamptz,
  'heavy abort applies r2_cooldown_until');

-- 12. retire_room cleans up active R2 media and upload locks
do $$
declare
  v_room3 public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  -- Clear cooldown for test
  update public.profiles set r2_cooldown_until = null where id = (select v from t where k = 'host');
  v_room3 := public.create_room('Host Room 3', 60);
  insert into t values ('room3', v_room3.id);
  perform public.set_room_media(v_room3.id, 'local', 'movie3.mp4', 1000);

  perform pg_temp.act_as_service_role();
  perform public.request_upload_slot(
    v_room3.id,
    (select v from t where k = 'host'),
    50000000::bigint,
    'rooms/r3/movie3.mp4',
    'upload_id_4'
  );
  perform public.set_media_upload_state(
    v_room3.id,
    (select v from t where k = 'host'),
    'ready',
    50000000::bigint,
    'rooms/r3/movie3.mp4',
    50000000::bigint
  );

  perform public.retire_room(v_room3.id);
end $$;

select is(
  (select count(*)::int from public.pending_r2_deletions where r2_key = 'rooms/r3/movie3.mp4'),
  1,
  'retire_room enqueues R2 key to pending_r2_deletions');

select is(
  (select media_upload_state from public.rooms where id = (select v from t where k = 'room3')),
  'none',
  'retire_room resets media_upload_state to none on dormant room');

select * from finish();
rollback;
