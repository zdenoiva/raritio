-- Make friend removal work directly from the client. The previous SECURITY
-- DEFINER function returned void but did not remove the row reliably.
grant select, delete on public.friendships to authenticated;

drop policy if exists "friendships_delete_own" on public.friendships;
create policy "friendships_delete_own" on public.friendships
  for delete using (auth.uid() = user_id);
