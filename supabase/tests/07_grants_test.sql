begin;
select plan(16);

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

select * from finish();
rollback;
