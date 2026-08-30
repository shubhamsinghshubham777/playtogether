revoke insert, update, delete on public.rooms from public, anon, authenticated;
revoke update, delete on public.tier_limits from public, anon, authenticated;
revoke insert, update, delete on public.subscriptions from public, anon, authenticated;

grant select on public.profiles to authenticated;
grant select on public.rooms to authenticated;
grant select on public.room_members to authenticated;
grant select, insert on public.messages to authenticated;
grant select on public.tier_limits to authenticated;
grant select on public.subscriptions to authenticated;

