-- Anonymous-user hygiene (abuse/bloat mitigation, Supabase-recommended):
-- purge guests older than 3 days. Guest rooms live <= 4 h, so anything
-- older is dead weight in auth.users/profiles.

-- Without cascade here, deleting any user who ever created a room fails on
-- this FK — which also silently broke the delete_account RPC for hosts.
-- A deleted account takes its rooms (and their members/messages) with it.
alter table public.rooms
  drop constraint rooms_created_by_fkey,
  add constraint rooms_created_by_fkey
    foreign key (created_by) references public.profiles (id) on delete cascade;

select cron.schedule(
  'purge-stale-guests',
  '17 3 * * *',
  $$ delete from auth.users
     where is_anonymous and created_at < now() - interval '3 days'; $$
);
