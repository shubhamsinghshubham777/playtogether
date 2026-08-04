create or replace function public.room_member_tiers(p_room_id uuid)
returns table (user_id uuid, tier text)
language sql stable security definer set search_path = ''
as $$
  select m.user_id, public.effective_tier(m.user_id)
  from public.room_members m
  where m.room_id = p_room_id
    and auth.uid() is not null
    and exists (
      select 1 from public.room_members me
      where me.room_id = p_room_id and me.user_id = auth.uid()
    );
$$;

revoke execute on function public.room_member_tiers(uuid) from public, anon;
grant execute on function public.room_member_tiers(uuid) to authenticated;
