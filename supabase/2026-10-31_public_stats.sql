-- Raritio 0.4.1 - aggregate public statistics for the hidden stats panel.
-- Only counts are exposed; no user identifiers or personal data.

create or replace function public.get_public_stats()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'sharedBinders', (
      select count(*) from public.shared_binders where is_active = true
    ),
    'sharedCards', (
      select coalesce(sum(card_count), 0)
      from public.shared_binders
      where is_active = true
    ),
    'friends', (select count(*) / 2 from public.friendships),
    'likes', (select count(*) from public.shared_card_likes)
  );
$$;

revoke all on function public.get_public_stats() from public;
grant execute on function public.get_public_stats() to authenticated;
