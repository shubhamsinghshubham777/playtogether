begin;
select plan(58);

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
declare v_free uuid; v_guest uuid; v_premium uuid; v_lapsed uuid;
begin
  v_free := pg_temp.mk_user();
  v_guest := pg_temp.mk_user(true);
  v_premium := pg_temp.mk_user();
  v_lapsed := pg_temp.mk_user();
  insert into t values ('free', v_free), ('guest', v_guest),
                       ('premium', v_premium), ('lapsed', v_lapsed);
  perform pg_temp.grant_premium(v_premium);
  perform pg_temp.grant_premium(v_lapsed, now() - interval '1 day');
end $$;

select is(
  public.effective_tier((select v from t where k = 'free')),
  'free',
  'a signed-in user with no subscription is free');

select is(
  public.effective_tier((select v from t where k = 'guest')),
  'guest',
  'an anonymous user is a guest whatever their subscription says');

select is(
  public.effective_tier((select v from t where k = 'premium')),
  'premium',
  'an open-ended subscription reads as premium');

select is(
  public.effective_tier((select v from t where k = 'lapsed')),
  'free',
  'a subscription past its period end falls back to free');

select is(
  public.effective_tier(null::uuid),
  'guest',
  'an unknown caller is treated as a guest');

do $$
declare v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'premium'));
  v_room := public.create_room('Premium room', 240);
  insert into t values ('premium_room', v_room.id);
  insert into c values ('premium_code', v_room.code);
end $$;

select is(
  (select max_members || ':' || av_level || ':' || persistent::text
   from public.rooms where id = (select v from t where k = 'premium_room')),
  '16:video:true',
  'a premium host stamps the 16-member cap, video AV and persistence onto the room');

select is(
  (select tier from public.my_entitlement()),
  'premium',
  'my_entitlement resolves the caller tier');

do $$
declare v_user uuid; i int;
begin
  for i in 1..8 loop
    v_user := pg_temp.mk_user();
    perform pg_temp.act_as(v_user);
    perform public.join_room((select v from c where k = 'premium_code'));
  end loop;
end $$;

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'premium_room')),
  9::bigint,
  'a premium room takes more than the eight a free room would');

do $$
declare v_user uuid; i int;
begin
  for i in 1..7 loop
    v_user := pg_temp.mk_user();
    perform pg_temp.act_as(v_user);
    perform public.join_room((select v from c where k = 'premium_code'));
  end loop;
  v_user := pg_temp.mk_user();
  perform pg_temp.act_as(v_user);
end $$;

select throws_ok(
  $$ select public.join_room((select v from c where k = 'premium_code')) $$,
  'room_full',
  'the seventeenth watcher is turned away from a premium room');

do $$
declare v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'free'));
  v_room := public.create_room('Free room', 60);
  insert into t values ('free_room', v_room.id);
  insert into c values ('free_code', v_room.code);
end $$;

select is(
  (select duration_minutes from public.extend_room(
     (select v from t where k = 'free_room'), 240)),
  120,
  'a free extension is a fixed hour, whatever was asked for');

select ok(
  (select expires_at - created_at from public.rooms
   where id = (select v from t where k = 'free_room')) = interval '120 minutes',
  'the extension moves expiry by the same hour');

select ok(
  (select free_extension_used from public.profiles where id = (select v from t where k = 'free')),
  'the one free extension is spent');

select throws_ok(
  $$ select public.extend_room((select v from t where k = 'free_room'), 60) $$,
  'extension_used',
  'the free tier only gets one extension, ever');

do $$ begin perform pg_temp.act_as((select v from t where k = 'premium')); end $$;

select is(
  (select duration_minutes from public.extend_room(
     (select v from t where k = 'premium_room'), 120)),
  360,
  'a premium host extends by the minutes they asked for');

select throws_ok(
  $$ select public.extend_room((select v from t where k = 'premium_room'), 1200) $$,
  'extension_cap',
  'a premium session cannot pass the total-minutes ceiling');

select throws_ok(
  $$ select public.extend_room((select v from t where k = 'free_room'), 60) $$,
  'not_host',
  'only the host may extend a room');

do $$
declare v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'guest'));
  v_room := public.create_room('Guest room', 60);
  insert into t values ('guest_room', v_room.id);
end $$;

select throws_ok(
  $$ select public.extend_room((select v from t where k = 'guest_room'), 30) $$,
  'extend_not_allowed',
  'a guest room cannot be extended at all');

do $$
begin
  insert into public.messages (room_id, sender_id, content)
  values ((select v from t where k = 'free_room'), (select v from t where k = 'free'), 'hello');
  update public.rooms set expires_at = now() - interval '1 minute'
    where id in ((select v from t where k = 'free_room'),
                 (select v from t where k = 'guest_room'),
                 (select v from t where k = 'premium_room'));
end $$;

select is(
  (select public.room_state(r) from public.rooms r
   where r.id = (select v from t where k = 'free_room')),
  'dormant',
  'a free room past its expiry is dormant even before sweep_rooms runs');

do $$
begin
  perform public.sweep_rooms();
end $$;

select is(
  (select public.room_state(r) from public.rooms r
   where r.id = (select v from t where k = 'free_room')),
  'dormant',
  'a free room past its expiry goes dormant rather than dying');

select ok(
  (select resumable_until from public.rooms where id = (select v from t where k = 'free_room'))
    > now() + interval '23 hours',
  'a dormant free room stays resumable for a day');

select is(
  (select count(*) from public.messages where room_id = (select v from t where k = 'free_room')),
  0::bigint,
  'chat is session-scoped: dormancy wipes the transcript');

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'free_room')),
  1::bigint,
  'dormancy keeps the membership, so the room can be resumed and rejoined');

select is(
  (select count(*) from public.rooms where id = (select v from t where k = 'guest_room')),
  0::bigint,
  'a guest room is deleted outright when it expires');

select is(
  (select public.room_state(r) || ':' || r.persistent::text from public.rooms r
   where r.id = (select v from t where k = 'premium_room')),
  'dormant:true',
  'a persistent room stays dormant with no resumable deadline');

do $$ begin perform pg_temp.act_as((select v from t where k = 'premium')); end $$;

select throws_ok(
  $$ select public.join_room((select v from c where k = 'free_code')) $$,
  'room_dormant',
  'a dormant room has to be resumed before anyone can join it');

do $$ begin perform pg_temp.act_as((select v from t where k = 'free')); end $$;

select throws_ok(
  $$ select public.resume_room((select v from t where k = 'free_room'), 600) $$,
  'invalid_duration',
  'a resumed session is capped by the tier like any other');

do $$
begin
  perform public.resume_room((select v from t where k = 'free_room'), 90);
end $$;

select is(
  (select public.room_state(r) from public.rooms r
   where r.id = (select v from t where k = 'free_room')),
  'live',
  'resuming a dormant room brings it back to life');

select is(
  (select coalesce(ended_at::text, '-') || coalesce(resumable_until::text, '-')
   from public.rooms where id = (select v from t where k = 'free_room')),
  '--',
  'resuming clears both the end stamp and the dormancy deadline');

do $$ begin perform pg_temp.act_as((select v from t where k = 'premium')); end $$;

select throws_ok(
  $$ select public.resume_room((select v from t where k = 'free_room'), 60) $$,
  'not_host',
  'only the host may resume a room');

do $$
begin
  perform pg_temp.act_as((select v from t where k = 'lapsed'));
  perform pg_temp.grant_premium((select v from t where k = 'lapsed'));
  insert into t values ('lapsed_room', (public.create_room('Lapsing room', 60)).id);
  delete from public.subscriptions where user_id = (select v from t where k = 'lapsed');
  update public.rooms set expires_at = now() - interval '1 minute'
    where id = (select v from t where k = 'lapsed_room');
  perform public.sweep_rooms();
end $$;

select ok(
  (select not persistent and resumable_until > now() + interval '6 days'
   from public.rooms where id = (select v from t where k = 'lapsed_room')),
  'a persistent room whose owner lapsed gets a seven-day grace instead of vanishing');

do $$
begin
  update public.rooms set resumable_until = now() - interval '1 minute'
    where id = (select v from t where k = 'lapsed_room');
  perform public.sweep_rooms();
end $$;

select is(
  (select count(*) from public.rooms where id = (select v from t where k = 'lapsed_room')),
  0::bigint,
  'once the grace is up the sweep deletes the room');

do $$
declare v_member uuid; v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'free'));
  v_room := public.create_room('Position room', 60);
  insert into t values ('pos_room', v_room.id);
  v_member := pg_temp.mk_user();
  insert into t values ('pos_member', v_member);
  perform pg_temp.act_as(v_member);
  perform public.join_room(v_room.code);
  perform public.update_media_position(v_room.id, 90000);
end $$;

select is(
  (select media_position_ms from public.rooms where id = (select v from t where k = 'pos_room')),
  90000::bigint,
  'any member may record where the room got to');

select isnt(
  (select media_position_at from public.rooms where id = (select v from t where k = 'pos_room')),
  null::timestamptz,
  'the position carries a server-clock stamp');

select throws_ok(
  $$ select public.update_media_position((select v from t where k = 'pos_room'), -1) $$,
  'invalid_position',
  'a negative position is rejected');

do $$
begin
  perform pg_temp.act_as((select v from t where k = 'free'));
  perform public.set_room_media((select v from t where k = 'pos_room'), 'local', 'other.mkv');
end $$;

select is(
  (select media_position_ms from public.rooms where id = (select v from t where k = 'pos_room')),
  null::bigint,
  'changing what the room watches drops the position it had reached');

do $$
declare v_outsider uuid;
begin
  v_outsider := pg_temp.mk_user();
  insert into t values ('outsider', v_outsider);
  perform pg_temp.act_as(v_outsider);
end $$;

select throws_ok(
  $$ select public.update_media_position((select v from t where k = 'pos_room'), 1000) $$,
  'not_a_member',
  'a stranger cannot write a position into a room they are not in');

select throws_ok(
  $$ select public.delete_room((select v from t where k = 'pos_room')) $$,
  'not_owner',
  'a stranger cannot delete a room');

do $$ begin perform pg_temp.act_as((select v from t where k = 'pos_member')); end $$;

select throws_ok(
  $$ select public.delete_room((select v from t where k = 'pos_room')) $$,
  'not_owner',
  'a plain member cannot delete the room either');

select is(
  (select count(*) from public.list_my_rooms()),
  1::bigint,
  'list_my_rooms shows only the rooms the caller belongs to');

select is(
  (select state || ':' || role || ':' || member_count::text from public.list_my_rooms()),
  'live:member:2',
  'each listed room carries its state, the caller role and the head count');

do $$ begin perform pg_temp.act_as((select v from t where k = 'free')); end $$;

select is(
  (select count(*) from public.list_my_rooms()
   where id = (select v from t where k = 'free_room')),
  1::bigint,
  'a resumed room is listed for its host');

do $$
begin
  perform public.delete_room((select v from t where k = 'pos_room'));
end $$;

select is(
  (select count(*) from public.rooms where id = (select v from t where k = 'pos_room')),
  0::bigint,
  'the room creator can delete a room outright, in any state');

do $$
declare v_owner uuid; v_heir uuid; v_room public.rooms;
begin
  v_owner := pg_temp.mk_user();
  v_heir := pg_temp.mk_user();
  insert into t values ('succ_owner', v_owner), ('heir', v_heir);
  perform pg_temp.act_as(v_owner);
  v_room := public.create_room('Succession room', 60);
  insert into t values ('succ_room', v_room.id);
  perform pg_temp.act_as(v_heir);
  perform public.join_room(v_room.code);
  perform pg_temp.act_as(v_owner);
  perform public.leave_room(v_room.id);
  perform pg_temp.act_as(v_heir);
end $$;

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'succ_room')
     and user_id = (select v from t where k = 'heir')),
  'host',
  'leaving hands the room to the next member, as before');

select throws_ok(
  $$ select public.delete_room((select v from t where k = 'succ_room')) $$,
  'not_owner',
  'an acting host who did not create the room cannot delete it');

select lives_ok(
  $$ select public.end_room((select v from t where k = 'succ_room')) $$,
  'an acting host can still end the session, which is the power they do have');

do $$
declare v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'succ_owner'));
  v_room := public.create_room('Doomed room', 60);
  insert into t values ('doomed_room', v_room.id);
  delete from realtime.messages;
  perform public.delete_room(v_room.id);
end $$;

select is(
  (select count(*) from realtime.messages
   where event = 'room_ended'
     and topic = 'room:' || (select v from t where k = 'doomed_room')::text),
  1::bigint,
  'deleting a room tells everyone still in it, before the row disappears');

select is(
  (select payload ->> 'reason' from realtime.messages
   where topic = 'room:' || (select v from t where k = 'doomed_room')::text),
  'deleted',
  'the eviction carries a reason, so the copy can say the room is gone for good');

do $$
declare v_ghost uuid; v_room public.rooms;
begin
  v_ghost := pg_temp.mk_user(true);
  insert into t values ('ghost', v_ghost);
  perform pg_temp.act_as(v_ghost);
  v_room := public.create_room('Abandoned room', 60);
  insert into t values ('abandoned_room', v_room.id);
  perform public.leave_room(v_room.id);
end $$;

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'abandoned_room')),
  0::bigint,
  'leaving your own room really does drop the membership row');

select is(
  (select count(*) from public.list_my_rooms()
   where id = (select v from t where k = 'abandoned_room')),
  1::bigint,
  'a room you created but left is still listed, or its cap would trap you with no way out');

select is(
  (select is_member from public.list_my_rooms()
   where id = (select v from t where k = 'abandoned_room')),
  false,
  'the listing says you are not in it, so the client rejoins rather than opening a channel it cannot authorize');

select is(
  (select is_owner from public.list_my_rooms()
   where id = (select v from t where k = 'abandoned_room')),
  true,
  'ownership survives leaving, which is what keeps delete_room reachable');

select throws_ok(
  $$ select public.create_room('Second guest room', 60) $$,
  'guest_room_limit',
  'the abandoned room still counts against the cap, so the listing and the cap now agree');

do $$ begin perform pg_temp.act_as((select v from t where k = 'free')); end $$;

select is(
  (select count(*) from public.list_my_rooms()
   where id = (select v from t where k = 'abandoned_room')),
  0::bigint,
  'a room someone else abandoned is not listed for anyone but its owner');

do $$
declare v_ender uuid; v_room public.rooms;
begin
  v_ender := pg_temp.mk_user(true);
  insert into t values ('ender', v_ender);
  perform pg_temp.act_as(v_ender);
  v_room := public.create_room('Room to end', 60);
  insert into t values ('ender_room', v_room.id);
  perform public.leave_room(v_room.id);
end $$;

select lives_ok(
  $$ select public.end_room((select v from t where k = 'ender_room')) $$,
  'the creator can end a room they have left, which is the only way out of their own cap');

select is(
  (select count(*) from public.rooms where id = (select v from t where k = 'ender_room')),
  0::bigint,
  'and a guest room is deleted outright at retirement, so the cap is genuinely freed');

do $$
declare v_owner uuid; v_member uuid; v_room public.rooms;
begin
  v_owner := pg_temp.mk_user();
  v_member := pg_temp.mk_user();
  insert into t values ('end_owner', v_owner), ('end_member', v_member);
  perform pg_temp.act_as(v_owner);
  v_room := public.create_room('Guarded room', 60);
  insert into t values ('guarded_room', v_room.id);
  perform pg_temp.act_as(v_member);
  perform public.join_room(v_room.code);
end $$;

select throws_ok(
  $$ select public.end_room((select v from t where k = 'guarded_room')) $$,
  'not_host',
  'a plain member still cannot end the room — the creator branch widened nothing else');

do $$ begin perform pg_temp.act_as((select v from t where k = 'free')); end $$;

select throws_ok(
  $$ select public.end_room((select v from t where k = 'guarded_room')) $$,
  'not_host',
  'and a stranger certainly cannot');

do $$ begin perform pg_temp.act_as((select v from t where k = 'end_member')); end $$;

select throws_ok(
  $$ select public.delete_room((select v from t where k = 'guarded_room')) $$,
  'not_owner',
  'ending is not deleting: a member who inherits the room still never gets delete');

select * from finish();
rollback;
