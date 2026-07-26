-- Ended-room hygiene: the expire-rooms sweep and end_room only set ended_at,
-- so rooms created by non-guest users (and their messages/members/bans, all
-- cascade-FK'd to rooms) piled up forever. No UI ever reads ended rooms, so
-- purge them after a 1-day grace period — long enough that a client mid-
-- reconnect still resolves the room as "ended" instead of "not found".

select cron.schedule(
  'purge-ended-rooms',
  '23 3 * * *',
  $$ delete from public.rooms
     where ended_at is not null and ended_at < now() - interval '1 day'; $$
);
