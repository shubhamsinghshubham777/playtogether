alter publication supabase_realtime add table public.subscriptions;
alter table public.subscriptions replica identity full;
