begin;
select plan(8);

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
begin
  v_host := pg_temp.mk_user(false);
  insert into t values ('host', v_host);
end $$;

-- 1. Direct delete from public.rooms enqueues media to pending_r2_deletions
do $$
declare
  v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  v_room := public.create_room('Direct Delete Room', 60);
  insert into t values ('room1', v_room.id);
  perform public.set_room_media(v_room.id, 'local', 'video1.mp4', 5000);

  perform pg_temp.act_as_service_role();
  perform public.request_upload_slot(
    v_room.id,
    (select v from t where k = 'host'),
    1000000::bigint,
    'rooms/r1/video1.mp4',
    'upload_id_101'
  );
  perform public.set_media_upload_state(
    v_room.id,
    (select v from t where k = 'host'),
    'ready',
    1000000::bigint,
    'rooms/r1/video1.mp4',
    1000000::bigint
  );

  -- Directly delete the room from the table
  delete from public.rooms where id = v_room.id;
end $$;

select is(
  (select count(*)::int from public.pending_r2_deletions where r2_key = 'rooms/r1/video1.mp4'),
  1,
  'direct delete from public.rooms triggers insertion into pending_r2_deletions');

-- 2. delete_room() RPC enqueues media to pending_r2_deletions
do $$
declare
  v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  v_room := public.create_room('RPC Delete Room', 60);
  insert into t values ('room2', v_room.id);
  perform public.set_room_media(v_room.id, 'local', 'video2.mp4', 5000);

  perform pg_temp.act_as_service_role();
  perform public.request_upload_slot(
    v_room.id,
    (select v from t where k = 'host'),
    2000000::bigint,
    'rooms/r2/video2.mp4',
    'upload_id_102'
  );
  perform public.set_media_upload_state(
    v_room.id,
    (select v from t where k = 'host'),
    'ready',
    2000000::bigint,
    'rooms/r2/video2.mp4',
    2000000::bigint
  );

  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.delete_room(v_room.id);
end $$;

select is(
  (select count(*)::int from public.pending_r2_deletions where r2_key = 'rooms/r2/video2.mp4'),
  1,
  'delete_room RPC triggers insertion into pending_r2_deletions via room trigger');

-- 3. Delete unclaimed staged upload enqueues to pending_r2_deletions
do $$
declare
  v_staged_id uuid;
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  insert into public.staged_media_uploads (
    user_id, file_name, file_size, duration_ms, r2_key, upload_id, upload_state, expires_at
  ) values (
    (select v from t where k = 'host'),
    'staged_sample.mp4',
    3000000,
    60000,
    'users/u1/staged/sample.mp4',
    'upload_id_103',
    'ready',
    now() + interval '1 hour'
  ) returning id into v_staged_id;

  insert into t values ('staged1', v_staged_id);

  -- Delete unclaimed staged upload
  delete from public.staged_media_uploads where id = v_staged_id;
end $$;

select is(
  (select count(*)::int from public.pending_r2_deletions where r2_key = 'users/u1/staged/sample.mp4'),
  1,
  'delete unclaimed staged upload triggers insertion into pending_r2_deletions');

-- 4. Delete claimed staged upload does not duplicate pending_r2_deletions
do $$
declare
  v_staged_id uuid;
  v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  insert into public.staged_media_uploads (
    user_id, file_name, file_size, duration_ms, r2_key, upload_id, upload_state, expires_at
  ) values (
    (select v from t where k = 'host'),
    'claimed_sample.mp4',
    4000000,
    120000,
    'users/u1/staged/claimed.mp4',
    null,
    'ready',
    now() + interval '1 hour'
  ) returning id into v_staged_id;

  v_room := public.create_room('Claimed Staged Room', 60, v_staged_id);
  insert into t values ('room4', v_room.id);

  -- Delete the staged upload record (now claimed)
  delete from public.staged_media_uploads where id = v_staged_id;
end $$;

select is(
  (select count(*)::int from public.pending_r2_deletions where r2_key = 'users/u1/staged/claimed.mp4'),
  0,
  'delete claimed staged upload does not enqueue to pending_r2_deletions (handled by room)');

-- 5. Deleting the room that claimed the staged media enqueues to pending_r2_deletions
do $$
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.delete_room((select v from t where k = 'room4'));
end $$;

select is(
  (select count(*)::int from public.pending_r2_deletions where r2_key = 'users/u1/staged/claimed.mp4'),
  1,
  'deleting room that claimed staged media triggers pending_r2_deletions');

-- 6. Helper function invoke_r2_cleanup executes cleanly
do $$
begin
  perform public.invoke_r2_cleanup();
end $$;

select pass('invoke_r2_cleanup executes without errors');

-- 7. App settings for r2_cleanup exists
select is(
  (select (value->>'enabled')::boolean from public.app_settings where key = 'r2_cleanup'),
  true,
  'app_settings r2_cleanup enabled defaults to true');

-- 8. Cron job is scheduled
select is(
  (select count(*)::int from cron.job where jobname = 'invoke-r2-cleanup'),
  1,
  'invoke-r2-cleanup cron job is scheduled');

select * from finish();
rollback;
