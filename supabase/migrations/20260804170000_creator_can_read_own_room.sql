drop policy if exists "members can read their rooms" on public.rooms;

create policy "members and creators can read their rooms"
  on public.rooms for select to authenticated
  using (public.is_room_member(id) or created_by = (select auth.uid()));
