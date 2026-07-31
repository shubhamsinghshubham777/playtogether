begin;
select plan(24);

create function pg_temp.mk_user(p_guest boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (
    v_id,
    p_guest,
    case when p_guest then null else 'u' || replace(v_id::text, '-', '') || '@example.test' end,
    '{}'::jsonb);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

create function pg_temp.act_as_nobody() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
end $$;

create temp table t (k text primary key, v uuid);

do $$
declare v_owner uuid; v_room uuid;
begin
  v_owner := pg_temp.mk_user();
  insert into t values ('owner', v_owner);
  perform pg_temp.act_as(v_owner);
  v_room := (public.create_room('Movie night', 60)).id;
  insert into t values ('room', v_room);
end $$;

select isnt_empty(
  $$ select 1 from public.rooms where id = (select v from t where k = 'room') $$,
  'create_room persists the room');

select is(
  (select created_by from public.rooms where id = (select v from t where k = 'room')),
  (select v from t where k = 'owner'),
  'the caller owns the room');

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'owner')),
  'host',
  'the creator joins as host');

select is(
  (select count(*) from public.room_members where room_id = (select v from t where k = 'room')),
  1::bigint,
  'a fresh room has exactly one member');

select matches(
  (select code from public.rooms where id = (select v from t where k = 'room')),
  '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$',
  'the join code is 6 chars from the unambiguous alphabet');

select is(
  (select name from public.rooms where id = (select v from t where k = 'room')),
  'Movie night',
  'the room name is stored');

select is(
  (select duration_minutes from public.rooms where id = (select v from t where k = 'room')),
  60,
  'the duration is stored');

select is(
  (select expires_at - created_at from public.rooms where id = (select v from t where k = 'room')),
  interval '60 minutes',
  'expiry is created_at plus the duration, on the server clock');

select is(
  (select media_kind from public.rooms where id = (select v from t where k = 'room')),
  'none',
  'a new room has no canonical media');

select is(
  (select transport_lock from public.rooms where id = (select v from t where k = 'room')),
  false,
  'a new room does not hold the remote');

select is(
  (select ended_at from public.rooms where id = (select v from t where k = 'room')),
  null::timestamptz,
  'a new room is live');

select is(
  (select name from public.create_room('   ', 60)),
  'Watch party',
  'a blank name falls back to the default');

select is(
  (select name from public.create_room('  Padded  ', 60)),
  'Padded',
  'the name is trimmed');

select lives_ok(
  $$ select public.create_room('Shortest', 5) $$,
  'the 5 minute floor is allowed');

select lives_ok(
  $$ select public.create_room('Longest', 240) $$,
  'the 4 hour ceiling is allowed');

select throws_ok(
  $$ select public.create_room('Too short', 4) $$,
  'invalid_duration',
  'a duration under 5 minutes is rejected');

select throws_ok(
  $$ select public.create_room('Too long', 241) $$,
  'invalid_duration',
  'a duration over 4 hours is rejected');

select throws_ok(
  $$ select public.create_room('No duration', null) $$,
  'invalid_duration',
  'a null duration is rejected');

select throws_ok(
  $$ select public.create_room('Negative', -60) $$,
  'invalid_duration',
  'a negative duration is rejected');

select lives_ok(
  $$ select public.create_room('Second room', 60) $$,
  'a signed-in user may hold several live rooms');

do $$
declare v_guest uuid;
begin
  v_guest := pg_temp.mk_user(true);
  insert into t values ('guest', v_guest);
  perform pg_temp.act_as(v_guest);
end $$;

select lives_ok(
  $$ select public.create_room('Guest room', 60) $$,
  'a guest may host one live room');

select throws_ok(
  $$ select public.create_room('Guest second room', 60) $$,
  'guest_room_limit',
  'a guest may not host a second live room');

do $$
begin
  update public.rooms set ended_at = now()
  where created_by = (select v from t where k = 'guest');
end $$;

select lives_ok(
  $$ select public.create_room('Guest room again', 60) $$,
  'the guest limit counts live rooms only, so ending one frees the slot');

do $$ begin perform pg_temp.act_as_nobody(); end $$;

select throws_ok(
  $$ select public.create_room('Anonymous', 60) $$,
  'not_authenticated',
  'an unauthenticated caller cannot create a room');

select * from finish();
rollback;
