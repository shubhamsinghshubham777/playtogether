begin;
select plan(15);

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

create temp table t (k text primary key, v uuid);

do $$
declare
  v_host uuid;
  v_guest uuid;
begin
  v_host := pg_temp.mk_user(false);
  v_guest := pg_temp.mk_user(true);
  insert into t values ('host', v_host), ('guest', v_guest);
end $$;

-- 1. Table exists and is protected by RLS
select has_table('public', 'staged_media_uploads', 'staged_media_uploads table exists');

-- 2. Request staged upload slot for guest (unauthorized)
select is(
  (public.request_staged_upload_slot((select v from t where k = 'guest'), 1000000, 'movie.mp4')->>'error'),
  'tier_unauthorized',
  'guest cannot request staged upload slot');

-- 3. Request staged upload slot for free host
select is(
  (public.request_staged_upload_slot((select v from t where k = 'host'), 1000000, 'movie.mp4')->>'allowed')::boolean,
  true,
  'free user can request staged upload slot');

-- Verify active upload lock is set on profile
select is(
  (select (active_upload_staged_id is not null) from public.profiles where id = (select v from t where k = 'host')),
  true,
  'profile has active staged upload lock set');

-- 4. A new staged upload automatically replaces / clears any previous incomplete staged upload
select is(
  (public.request_staged_upload_slot((select v from t where k = 'host'), 1000000, 'movie.mp4')->>'allowed')::boolean,
  true,
  'requesting new staged upload slot replaces previous unfinished staged upload');

-- 5. Mark staged upload as ready
do $$
declare
  v_staged_id uuid;
begin
  select id into v_staged_id from public.staged_media_uploads where user_id = (select v from t where k = 'host');
  perform public.set_staged_upload_state(v_staged_id, (select v from t where k = 'host'), 'ready', 1000000, 'users/host/staged/1-movie.mp4');
  insert into t values ('staged_id', v_staged_id);
end $$;

select is(
  (select upload_state from public.staged_media_uploads where id = (select v from t where k = 'staged_id')),
  'ready',
  'staged upload state is marked ready');

-- Verify lock cleared and quota debited
select is(
  (select active_upload_staged_id from public.profiles where id = (select v from t where k = 'host')),
  null,
  'active upload lock is cleared on completion');

select is(
  (select r2_upload_bytes_7d from public.profiles where id = (select v from t where k = 'host')),
  1000000::bigint,
  'upload bytes quota is debited on completion');

-- 6. Create room claiming the staged media upload
do $$
declare
  v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  v_room := public.create_room('Staged Party', 60, (select v from t where k = 'staged_id'));
  insert into t values ('room_id', v_room.id);
end $$;

select is(
  (select media_upload_state from public.rooms where id = (select v from t where k = 'room_id')),
  'ready',
  'created room has media_upload_state = ready');

select is(
  (select media_name from public.rooms where id = (select v from t where k = 'room_id')),
  'movie.mp4',
  'created room has media_name populated from staged upload');

select is(
  (select claimed_room_id from public.staged_media_uploads where id = (select v from t where k = 'staged_id')),
  (select v from t where k = 'room_id'),
  'staged upload is marked claimed by the room');

-- 7. Cannot claim the same staged upload twice
select throws_ok(
  format('select public.create_room(''Second Room'', 60, %L::uuid)', (select v from t where k = 'staged_id')),
  'staged_media_invalid',
  'cannot claim already claimed staged upload');

-- 8. Clear staged upload test
do $$
declare
  v_slot jsonb;
  v_new_staged_id uuid;
begin
  v_slot := public.request_staged_upload_slot((select v from t where k = 'host'), 2000000, 'abort_test.mp4', null, 'users/host/staged/abort.mp4', 'upload_id_123');
  v_new_staged_id := (v_slot->>'staged_id')::uuid;
  perform public.clear_staged_upload(v_new_staged_id, 500000);
  insert into t values ('aborted_staged_id', v_new_staged_id);
end $$;

select is(
  (select count(*) from public.staged_media_uploads where id = (select v from t where k = 'aborted_staged_id')),
  0::bigint,
  'aborted staged upload row is deleted');

select is(
  (select count(*) from public.pending_r2_deletions where upload_id = 'upload_id_123'),
  1::bigint,
  'pending_r2_deletions enqueued incomplete upload');

select is(
  (select r2_consecutive_aborts from public.profiles where id = (select v from t where k = 'host')),
  1,
  'consecutive aborts counter incremented');

select * from finish();
rollback;
