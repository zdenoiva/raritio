-- Fix: friend_code was ambiguous between the function's OUT column and the
-- profiles table column. Qualify the table alias explicitly.
create or replace function public.add_friend_by_code(p_code text)
returns table(friend_id uuid, nickname text, friend_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.profiles;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select p.* into target
  from public.profiles p
  where upper(trim(p.friend_code)) = upper(trim(p_code))
  limit 1;

  if not found or target.id is null then
    raise exception 'FRIEND_NOT_FOUND';
  end if;
  if target.id = auth.uid() then
    raise exception 'SELF_FRIEND';
  end if;

  insert into public.friendships(user_id, friend_id)
  values (auth.uid(), target.id)
  on conflict do nothing;

  insert into public.friendships(user_id, friend_id)
  values (target.id, auth.uid())
  on conflict do nothing;

  return query select target.id, target.nickname, target.friend_code;
end;
$$;

grant execute on function public.add_friend_by_code(text) to authenticated;
