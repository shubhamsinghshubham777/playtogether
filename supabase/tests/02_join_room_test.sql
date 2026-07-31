begin;
select plan(18);

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

create temp table t (k text primary key, v uuid);
create temp table c (k text primary key, v text);

do $$
declare v_host uuid; v_room public.rooms;
begin
  v_host := pg_temp.mk_user();
  insert into t values ('host', v_host);
  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Movie night', 60);
  insert into t values ('room', v_room.id);
  insert into c values ('code', v_room.code);
end $$;

do $$
declare v_joiner uuid;
begin
  v_joiner := pg_temp.mk_user();
  insert into t values ('joiner', v_joiner);
  perform pg_temp.act_as(v_joiner);
  perform public.join_room((select v from c where k = 'code'));
end $$;

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'joiner')),
  'member',
  'a joiner is added as a plain member');

select is(
  (select count(*) from public.room_members where room_id = (select v from t where k = 'room')),
  2::bigint,
  'the room now has two members');

select lives_ok(
  $$ select public.join_room((select v from c where k = 'code')) $$,
  'rejoining as an existing member is fine');

select is(
  (select count(*) from public.room_members where room_id = (select v from t where k = 'room')),
  2::bigint,
  'rejoining does not duplicate the membership');

select throws_ok(
  $$ select public.join_room('ZZZZZZ') $$,
  'room_not_found',
  'an unknown code is rejected');

select throws_ok(
  $$ select public.join_room(null) $$,
  'room_not_found',
  'a null code is rejected');

do $$
declare v_host uuid; v_room public.rooms;
begin
  v_host := pg_temp.mk_user();
  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Ended room', 60);
  insert into c values ('ended_code', v_room.code);
  update public.rooms set ended_at = now() where id = v_room.id;

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Expired room', 60);
  insert into c values ('expired_code', v_room.code);
  update public.rooms set expires_at = now() - interval '1 minute' where id = v_room.id;
end $$;

do $$ begin perform pg_temp.act_as((select v from t where k = 'joiner')); end $$;

select throws_ok(
  $$ select public.join_room((select v from c where k = 'ended_code')) $$,
  'room_ended',
  'a room the host ended cannot be joined');

select throws_ok(
  $$ select public.join_room((select v from c where k = 'expired_code')) $$,
  'room_ended',
  'a room past its expiry cannot be joined, before the sweep has run');

do $$
declare v_full public.rooms; v_host uuid; v_user uuid; i int;
begin
  v_host := pg_temp.mk_user();
  perform pg_temp.act_as(v_host);
  v_full := public.create_room('Full room', 60);
  insert into c values ('full_code', v_full.code);

  for i in 1..7 loop
    v_user := pg_temp.mk_user();
    perform pg_temp.act_as(v_user);
    perform public.join_room(v_full.code);
  end loop;

  v_user := pg_temp.mk_user();
  insert into t values ('ninth', v_user);
  perform pg_temp.act_as(v_user);
end $$;

select is(
  (select count(*) from public.room_members
   where room_id = (select id from public.rooms where code = (select v from c where k = 'full_code'))),
  8::bigint,
  'the eighth member fills the room');

select throws_ok(
  $$ select public.join_room((select v from c where k = 'full_code')) $$,
  'room_full',
  'a ninth watcher is turned away');

do $$
declare v_banned uuid; v_room_id uuid;
begin
  v_room_id := (select v from t where k = 'room');
  v_banned := pg_temp.mk_user();
  insert into t values ('banned', v_banned);
  insert into public.room_bans (room_id, user_id) values (v_room_id, v_banned);
  perform pg_temp.act_as(v_banned);
end $$;

select throws_ok(
  $$ select public.join_room((select v from c where k = 'code')) $$,
  'room_banned',
  'a banned user cannot join');

do $$
declare v_still_member uuid; v_room_id uuid;
begin
  v_room_id := (select v from t where k = 'room');
  v_still_member := pg_temp.mk_user();
  insert into t values ('banned_member', v_still_member);
  insert into public.room_members (room_id, user_id, role)
    values (v_room_id, v_still_member, 'member');
  insert into public.room_bans (room_id, user_id) values (v_room_id, v_still_member);
  perform pg_temp.act_as(v_still_member);
end $$;

select throws_ok(
  $$ select public.join_room((select v from c where k = 'code')) $$,
  'room_banned',
  'the ban is checked before the already-a-member early return, so it cannot be walked around');

do $$
declare v_host uuid; v_room public.rooms; v_case uuid;
begin
  v_host := pg_temp.mk_user();
  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Case room', 60);
  insert into c values ('case_code', v_room.code);
  v_case := pg_temp.mk_user();
  insert into t values ('caser', v_case);
  perform pg_temp.act_as(v_case);
end $$;

select lives_ok(
  $$ select public.join_room(lower((select v from c where k = 'case_code'))) $$,
  'a lowercase code still joins');

select lives_ok(
  $$ select public.join_room('  ' || (select v from c where k = 'case_code') || '  ') $$,
  'a code with stray whitespace still joins');

select is(
  (select id from public.join_room((select v from c where k = 'case_code'))),
  (select id from public.rooms where code = (select v from c where k = 'case_code')),
  'join_room returns the room that was joined');

do $$
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  update public.room_members set role = 'host'
    where room_id = (select v from t where k = 'room')
      and user_id = (select v from t where k = 'host');
end $$;

select lives_ok(
  $$ select public.join_room((select v from c where k = 'code')) $$,
  'a host rejoining their own room is fine');

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'host')),
  'host',
  'rejoining never demotes the host');

do $$ begin perform set_config('request.jwt.claims', '', true); end $$;

select throws_ok(
  $$ select public.join_room((select v from c where k = 'code')) $$,
  'not_authenticated',
  'an unauthenticated caller cannot join');

select * from finish();
rollback;
