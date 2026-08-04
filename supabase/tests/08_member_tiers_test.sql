begin;
select plan(8);

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

create function pg_temp.grant_premium(p_uid uuid, p_ends timestamptz default null) returns void
language plpgsql as $$
begin
  insert into public.subscriptions (user_id, tier, current_period_end)
  values (p_uid, 'premium', p_ends)
  on conflict (user_id) do update set tier = 'premium', current_period_end = p_ends;
end $$;

create temp table t (k text primary key, v uuid);
create temp table c (k text primary key, v text);

do $$
declare
  v_host uuid; v_free uuid; v_guest uuid; v_lapsed uuid; v_outsider uuid;
  v_room public.rooms;
begin
  v_host := pg_temp.mk_user();
  v_free := pg_temp.mk_user();
  v_guest := pg_temp.mk_user(true);
  v_lapsed := pg_temp.mk_user();
  v_outsider := pg_temp.mk_user();
  insert into t values ('host', v_host), ('free', v_free), ('guest', v_guest),
                       ('lapsed', v_lapsed), ('outsider', v_outsider);

  perform pg_temp.grant_premium(v_host);
  perform pg_temp.grant_premium(v_guest);
  perform pg_temp.grant_premium(v_lapsed, now() - interval '1 day');

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Crown room', 240);
  insert into t values ('room', v_room.id);
  insert into c values ('code', v_room.code);

  perform pg_temp.act_as(v_free);
  perform public.join_room(v_room.code);
  perform pg_temp.act_as(v_guest);
  perform public.join_room(v_room.code);
  perform pg_temp.act_as(v_lapsed);
  perform public.join_room(v_room.code);
end $$;

do $$ begin perform pg_temp.act_as((select v from t where k = 'free')); end $$;

select is(
  (select count(*) from public.room_member_tiers((select v from t where k = 'room'))),
  4::bigint,
  'a member gets a tier for every member of the room, themselves included');

select is(
  (select tier from public.room_member_tiers((select v from t where k = 'room'))
   where user_id = (select v from t where k = 'host')),
  'premium',
  'a plain member can see that the host is premium');

select is(
  (select tier from public.room_member_tiers((select v from t where k = 'room'))
   where user_id = (select v from t where k = 'free')),
  'free',
  'a signed-in member with no subscription reads as free');

select is(
  (select tier from public.room_member_tiers((select v from t where k = 'room'))
   where user_id = (select v from t where k = 'guest')),
  'guest',
  'a guest never reads as premium, whatever subscription row exists for them');

select is(
  (select tier from public.room_member_tiers((select v from t where k = 'room'))
   where user_id = (select v from t where k = 'lapsed')),
  'free',
  'a lapsed subscription reads as free, so the crown goes away on its own');

do $$ begin perform pg_temp.act_as((select v from t where k = 'outsider')); end $$;

select is(
  (select count(*) from public.room_member_tiers((select v from t where k = 'room'))),
  0::bigint,
  'a stranger cannot enumerate who is premium in a room they are not in');

do $$ begin perform set_config('request.jwt.claims', null, true); end $$;

select is(
  (select count(*) from public.room_member_tiers((select v from t where k = 'room'))),
  0::bigint,
  'an unauthenticated caller gets nothing at all');

select ok(
  has_function_privilege('authenticated', 'public.room_member_tiers(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.room_member_tiers(uuid)', 'EXECUTE'),
  'the tier lookup is granted to signed-in clients and withheld from anon');

select * from finish();
rollback;
