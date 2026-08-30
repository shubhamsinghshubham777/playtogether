begin;
select plan(5);

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

-- Test 1: Privilege test
select ok(
  has_function_privilege('authenticated', 'public.debug_grant_premium(int)', 'EXECUTE'),
  'signed-in clients have execute privilege on debug_grant_premium');

-- Test 2: Gate test when app.settings.is_local is false
do $$
declare v_user uuid := pg_temp.mk_user();
begin
  perform pg_temp.act_as(v_user);
  perform set_config('app.settings.is_local', 'false', true);
end $$;

select throws_ok(
  'select public.debug_grant_premium(1)',
  'debug_grant_premium is only available on the local stack',
  'refuses to execute when is_local is false');

-- Test 3: Success when app.settings.is_local is true
do $$
declare v_user uuid := pg_temp.mk_user();
begin
  perform pg_temp.act_as(v_user);
  perform set_config('app.settings.is_local', 'true', true);
  perform public.debug_grant_premium(2);
  perform set_config('my.test_user', v_user::text, true);
end $$;

select is(
  public.effective_tier(current_setting('my.test_user')::uuid),
  'premium',
  'grants premium tier to caller when is_local is true');

select is(
  (select source from public.subscriptions where user_id = current_setting('my.test_user')::uuid),
  'debug',
  'subscription source is stamped as debug');

select ok(
  (select current_period_end > now() + interval '1 month' from public.subscriptions where user_id = current_setting('my.test_user')::uuid),
  'current_period_end is set in the future based on months parameter');

select * from finish();
rollback;
