begin;
select plan(25);

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

do $$
declare v_guest uuid; v_room public.rooms;
begin
  v_guest := pg_temp.mk_user(true);
  insert into t values ('solo_guest', v_guest);
  perform pg_temp.act_as(v_guest);
  v_room := public.create_room('Guest movie', 60);
  insert into t values ('solo_room', v_room.id);
  insert into c values ('solo_code', v_room.code);
  perform public.leave_room(v_room.id);
end $$;

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'solo_room') and role = 'host'),
  0::bigint,
  'the last member leaving leaves the room with nobody as host');

do $$ begin perform public.join_room((select v from c where k = 'solo_code')); end $$;

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'solo_room')
     and user_id = (select v from t where k = 'solo_guest')),
  'host',
  'walking back into your own empty room makes you its host again');

do $$
declare v_free uuid; v_other uuid; v_room public.rooms;
begin
  v_free := pg_temp.mk_user();
  v_other := pg_temp.mk_user();
  insert into t values ('free_owner', v_free), ('free_other', v_other);
  perform pg_temp.act_as(v_free);
  v_room := public.create_room('Free movie', 60);
  insert into t values ('free_room', v_room.id);
  insert into c values ('free_code', v_room.code);
  perform public.leave_room(v_room.id);
  perform pg_temp.act_as(v_other);
  perform public.join_room(v_room.code);
end $$;

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'free_room')
     and user_id = (select v from t where k = 'free_other')),
  'host',
  'the rule is tier-blind and not creator-only — whoever enters an empty room hosts it');

do $$ begin perform pg_temp.act_as((select v from t where k = 'free_owner')); end $$;
do $$ begin perform public.join_room((select v from c where k = 'free_code')); end $$;

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'free_room')
     and user_id = (select v from t where k = 'free_owner')),
  'member',
  'a creator returning to a room that already has a host does not take it back');

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'free_room') and role = 'host'),
  1::bigint,
  'and the room still has exactly one host, which authority election depends on');

do $$
declare v_prem uuid; v_room public.rooms;
begin
  v_prem := pg_temp.mk_user();
  insert into t values ('prem_owner', v_prem);
  insert into public.subscriptions (user_id, tier, current_period_end)
    values (v_prem, 'premium', now() + interval '30 days');
  perform pg_temp.act_as(v_prem);
  v_room := public.create_room('Premium movie', 60);
  insert into t values ('prem_room', v_room.id);
  insert into c values ('prem_code', v_room.code);
  perform public.leave_room(v_room.id);
  perform public.join_room(v_room.code);
end $$;

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'prem_room')
     and user_id = (select v from t where k = 'prem_owner')),
  'host',
  'premium re-entry restores the host role too');

do $$
declare v_heir uuid; v_room public.rooms;
begin
  v_heir := pg_temp.mk_user();
  insert into t values ('succ_heir', v_heir);
  perform pg_temp.act_as((select v from t where k = 'prem_owner'));
  v_room := public.create_room('Succession movie', 60);
  insert into t values ('succ_room2', v_room.id);
  insert into c values ('succ_code2', v_room.code);
  perform pg_temp.act_as(v_heir);
  perform public.join_room(v_room.code);
  perform pg_temp.act_as((select v from t where k = 'prem_owner'));
  perform public.leave_room(v_room.id);
  perform public.join_room(v_room.code);
end $$;

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'succ_room2')
     and user_id = (select v from t where k = 'succ_heir')),
  'host',
  'succession still wins: an heir who inherited the room keeps it when the creator returns');

select * from finish();
rollback;
