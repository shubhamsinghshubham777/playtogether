begin;
select plan(12);

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

do $$
declare v_host uuid; v_room public.rooms; v_early uuid; v_late uuid;
begin
  v_host := pg_temp.mk_user();
  v_early := pg_temp.mk_user();
  v_late := pg_temp.mk_user();
  insert into t values ('host', v_host), ('early', v_early), ('late', v_late);

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Succession', 60);
  insert into t values ('room', v_room.id);

  perform pg_temp.act_as(v_late);
  perform public.join_room(v_room.code);
  perform pg_temp.act_as(v_early);
  perform public.join_room(v_room.code);

  update public.room_members set joined_at = now() - interval '10 minutes'
    where room_id = v_room.id and user_id = v_early;
  update public.room_members set joined_at = now() - interval '1 minute'
    where room_id = v_room.id and user_id = v_late;
end $$;

do $$
begin
  perform pg_temp.act_as((select v from t where k = 'late'));
  perform public.leave_room((select v from t where k = 'room'));
end $$;

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'late')),
  0::bigint,
  'leaving removes the membership row');

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'host')),
  'host',
  'a plain member leaving does not disturb the host');

do $$
declare v_room_id uuid; v_extra uuid;
begin
  v_room_id := (select v from t where k = 'room');
  v_extra := pg_temp.mk_user();
  insert into t values ('extra', v_extra);
  insert into public.room_members (room_id, user_id, role, joined_at)
    values (v_room_id, v_extra, 'member', now() - interval '5 minutes');

  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.leave_room(v_room_id);
end $$;

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'host')),
  0::bigint,
  'the departing host is removed');

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'early')),
  'host',
  'host succession promotes the earliest joiner');

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'extra')),
  'member',
  'a later joiner is passed over');

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'room') and role = 'host'),
  1::bigint,
  'succession leaves exactly one host');

do $$
declare v_host uuid; v_room public.rooms;
begin
  v_host := pg_temp.mk_user();
  insert into t values ('solo', v_host);
  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Solo', 60);
  insert into t values ('solo_room', v_room.id);
end $$;

select lives_ok(
  $$ select public.leave_room((select v from t where k = 'solo_room')) $$,
  'the last member can leave without error');

select is(
  (select count(*) from public.room_members where room_id = (select v from t where k = 'solo_room')),
  0::bigint,
  'the room is left with no members');

select is(
  (select ended_at from public.rooms where id = (select v from t where k = 'solo_room')),
  null::timestamptz,
  'the last member leaving does not end the room — expiry and end_room own that');

select lives_ok(
  $$ select public.leave_room((select v from t where k = 'solo_room')) $$,
  'leaving twice is a no-op');

do $$
declare v_stranger uuid;
begin
  v_stranger := pg_temp.mk_user();
  perform pg_temp.act_as(v_stranger);
end $$;

select lives_ok(
  $$ select public.leave_room((select v from t where k = 'room')) $$,
  'leaving a room you were never in is a no-op');

select is(
  (select count(*) from public.room_members where room_id = (select v from t where k = 'room')),
  2::bigint,
  'a stranger leaving does not disturb the member list');

select * from finish();
rollback;
