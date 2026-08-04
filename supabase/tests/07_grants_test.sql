begin;
select plan(18);

select ok(
  has_table_privilege('authenticated', 'public.profiles', 'SELECT'),
  'signed-in clients can read profiles, which every screen needs');

select ok(
  has_table_privilege('authenticated', 'public.rooms', 'SELECT'),
  'signed-in clients can read rooms');

select ok(
  has_table_privilege('authenticated', 'public.room_members', 'SELECT'),
  'signed-in clients can read the member list');

select ok(
  has_table_privilege('authenticated', 'public.messages', 'SELECT'),
  'signed-in clients can read chat history');

select ok(
  has_table_privilege('authenticated', 'public.messages', 'INSERT'),
  'signed-in clients can post chat');

select ok(
  has_table_privilege('authenticated', 'public.tier_limits', 'SELECT'),
  'signed-in clients can read the tier table their entitlement resolves against');

select ok(
  has_table_privilege('authenticated', 'public.subscriptions', 'SELECT'),
  'signed-in clients can read their own subscription row');

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE'),
  'the profile fields a user owns stay writable');

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'avatar_url', 'UPDATE'),
  'the avatar stays writable');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'email', 'UPDATE'),
  'the email mirror is not user-editable, whatever RLS says');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'is_guest', 'UPDATE'),
  'nobody can promote themselves out of being a guest');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'free_extension_used', 'UPDATE'),
  'the one free extension cannot be handed back by the client that spent it');

select ok(
  not has_table_privilege('authenticated', 'public.room_bans', 'SELECT'),
  'the ban list stays unreadable by clients, grant as well as policy');

select ok(
  not has_table_privilege('authenticated', 'public.rooms', 'UPDATE'),
  'rooms are written only by the security-definer RPCs');

select ok(
  not has_table_privilege('authenticated', 'public.tier_limits', 'UPDATE'),
  'nobody can raise their own limits');

select ok(
  not has_table_privilege('authenticated', 'public.subscriptions', 'INSERT'),
  'nobody can grant themselves premium');

create function pg_temp.abandoned_room() returns uuid
language plpgsql as $$
declare v_u uuid := gen_random_uuid(); v_room public.rooms;
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_u, true, null, '{}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', v_u)::text, true);
  v_room := public.create_room('Abandoned', 60);
  perform public.leave_room(v_room.id);
  return v_room.id;
end $$;

create function pg_temp.rows_visible_as_authenticated(p_room_id uuid) returns int
language plpgsql as $$
declare v_cnt int;
begin
  set local role authenticated;
  select count(*) into v_cnt from public.rooms where id = p_room_id;
  reset role;
  return v_cnt;
end $$;

select is(
  pg_temp.rows_visible_as_authenticated(pg_temp.abandoned_room()),
  1,
  'RLS lets a creator read a room they have left — a plain table read is how the lobby finds the room blocking their cap');

create function pg_temp.visible_to_a_stranger(p_room_id uuid) returns int
language plpgsql as $$
declare v_other uuid := gen_random_uuid(); v_cnt int;
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_other, true, null, '{}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);
  set local role authenticated;
  select count(*) into v_cnt from public.rooms where id = p_room_id;
  reset role;
  return v_cnt;
end $$;

select is(
  pg_temp.visible_to_a_stranger(pg_temp.abandoned_room()),
  0,
  'and that visibility is scoped to the creator — a stranger still sees nothing');

select * from finish();
rollback;
