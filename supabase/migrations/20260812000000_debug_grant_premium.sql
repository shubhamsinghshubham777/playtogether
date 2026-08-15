create or replace function public.debug_grant_premium(p_months int default 1)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_server_ip inet;
begin
  -- Gate: only allow on local development stack or when explicitly permitted.
  if coalesce(current_setting('app.settings.is_local', true), '') = 'false' then
    raise exception 'debug_grant_premium is only available on the local stack';
  end if;

  v_server_ip := inet_server_addr();
  if v_server_ip is not null and not (
    v_server_ip <<= inet '127.0.0.0/8' or
    v_server_ip <<= inet '172.16.0.0/12' or
    v_server_ip <<= inet '192.168.0.0/16' or
    v_server_ip <<= inet '10.0.0.0/8'
  ) and coalesce(current_setting('app.settings.is_local', true), '') <> 'true' then
    raise exception 'debug_grant_premium is only available on the local stack';
  end if;

  insert into public.subscriptions (user_id, tier, source, current_period_end)
  values (auth.uid(), 'premium', 'debug', now() + make_interval(months => p_months))
  on conflict (user_id) do update
    set tier = 'premium',
        source = 'debug',
        current_period_end = excluded.current_period_end,
        updated_at = now();
end;
$$;

grant execute on function public.debug_grant_premium(int) to authenticated;
