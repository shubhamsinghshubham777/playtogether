begin;
select plan(16);

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
create temp table c (k text primary key, v text);

do $$
declare v_host uuid; v_room public.rooms; v_a uuid; v_b uuid;
begin
  v_host := pg_temp.mk_user();
  v_a := pg_temp.mk_user();
  v_b := pg_temp.mk_user();
  insert into t values ('host', v_host), ('a', v_a), ('b', v_b);

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Kick room', 60);
  insert into t values ('room', v_room.id);
  insert into c values ('code', v_room.code);

  perform pg_temp.act_as(v_a);
  perform public.join_room(v_room.code);
  perform pg_temp.act_as(v_b);
  perform public.join_room(v_room.code);

  perform pg_temp.act_as(v_host);
  perform public.kick_member(v_room.id, v_a, false);
end $$;

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'room') and user_id = (select v from t where k = 'a')),
  0::bigint,
  'a kick removes the membership row');

select is(
  (select count(*) from public.room_bans
   where room_id = (select v from t where k = 'room') and user_id = (select v from t where k = 'a')),
  0::bigint,
  'a kick without ban writes no ban row');

do $$ begin perform pg_temp.act_as((select v from t where k = 'a')); end $$;

select lives_ok(
  $$ select public.join_room((select v from c where k = 'code')) $$,
  'someone kicked without a ban may come back');

do $$
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.kick_member(
    (select v from t where k = 'room'), (select v from t where k = 'b'), true);
end $$;

select is(
  (select count(*) from public.room_bans
   where room_id = (select v from t where k = 'room') and user_id = (select v from t where k = 'b')),
  1::bigint,
  'a kick with ban writes the ban row');

do $$ begin perform pg_temp.act_as((select v from t where k = 'b')); end $$;

select throws_ok(
  $$ select public.join_room((select v from c where k = 'code')) $$,
  'room_banned',
  'a banned watcher cannot rejoin');

select throws_ok(
  $$ select public.kick_member(
       (select v from t where k = 'room'), (select v from t where k = 'a'), false) $$,
  'not_host',
  'a non-host cannot kick anyone');

do $$ begin perform pg_temp.act_as((select v from t where k = 'host')); end $$;

select throws_ok(
  $$ select public.kick_member(
       (select v from t where k = 'room'), (select v from t where k = 'host'), false) $$,
  'cannot_kick_self',
  'the host cannot kick themselves — leaving is the way out');

select throws_ok(
  $$ select public.kick_member((select v from t where k = 'room'), null, false) $$,
  'invalid_target',
  'a null target is rejected');

do $$
declare v_gone uuid;
begin
  v_gone := pg_temp.mk_user();
  insert into t values ('gone', v_gone);
end $$;

select lives_ok(
  $$ select public.kick_member(
       (select v from t where k = 'room'), (select v from t where k = 'gone'), true) $$,
  'kicking someone who already left is tolerated');

select is(
  (select count(*) from public.room_bans
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'gone')),
  1::bigint,
  'the ban is still recorded for a target who left first, since the ban is the part that matters');

select lives_ok(
  $$ select public.kick_member(
       (select v from t where k = 'room'), (select v from t where k = 'gone'), true) $$,
  'banning twice is idempotent');

do $$
declare v_host2 uuid; v_room2 public.rooms; v_member2 uuid;
begin
  v_host2 := pg_temp.mk_user();
  v_member2 := pg_temp.mk_user();
  insert into t values ('host2', v_host2), ('member2', v_member2);
  perform pg_temp.act_as(v_host2);
  v_room2 := public.create_room('Ended kick room', 60);
  insert into t values ('room2', v_room2.id);
  perform pg_temp.act_as(v_member2);
  perform public.join_room(v_room2.code);
  update public.rooms set ended_at = now() where id = v_room2.id;
  perform pg_temp.act_as(v_host2);
end $$;

select throws_ok(
  $$ select public.kick_member(
       (select v from t where k = 'room2'), (select v from t where k = 'member2'), false) $$,
  'room_ended',
  'nobody can be kicked from a room that has ended');

do $$ begin perform set_config('request.jwt.claims', '', true); end $$;

select throws_ok(
  $$ select public.kick_member(
       (select v from t where k = 'room'), (select v from t where k = 'a'), false) $$,
  'not_authenticated',
  'an unauthenticated caller cannot kick');

select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.room_bans'::regclass),
  'room_bans has row level security enabled');

select is(
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'room_bans'),
  0::bigint,
  'room_bans has deliberately no policies — a ban is never read by a client');

select ok(
  not has_table_privilege('authenticated', 'public.room_bans', 'select'),
  'the authenticated role cannot read the ban list even with RLS off');

select * from finish();
rollback;
