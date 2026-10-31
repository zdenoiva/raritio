-- Raritio 0.3.16 - account privacy and deletion
-- Remove optional email storage; accounts are identified by an anonymous
-- Supabase user, a generated friend code and a nickname only.

alter table public.profiles drop column if exists email;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- Owner-only share token access.
create or replace function public.get_my_shared_binders()
returns setof public.shared_binders
language sql
security definer
set search_path = public
as $$
  select *
  from public.shared_binders
  where owner_id = auth.uid()
  order by updated_at desc;
$$;

create or replace function public.get_my_shared_binder_token(p_binder_id uuid)
returns text
language sql
security definer
set search_path = public
as $$
  select share_token
  from public.shared_binders
  where id = p_binder_id and owner_id = auth.uid();
$$;

revoke all on function public.get_my_shared_binders() from public;
revoke all on function public.get_my_shared_binder_token(uuid) from public;
grant execute on function public.get_my_shared_binders() to authenticated;
grant execute on function public.get_my_shared_binder_token(uuid) to authenticated;

revoke select on public.shared_binders from authenticated;
grant select (
  id, owner_id, owner_nickname, name, snapshot, card_count, total_value,
  is_active, created_at, updated_at
) on public.shared_binders to authenticated;
grant insert, update, delete on public.shared_binders to authenticated;

-- The old implementation left friend access rows behind after removal.
create or replace function public.remove_friend(p_friend_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.shared_binder_access a
  where a.source = 'friend'
    and (
      (
        a.viewer_id = p_friend_id
        and exists (
          select 1 from public.shared_binders b
          where b.id = a.shared_binder_id and b.owner_id = auth.uid()
        )
      )
      or (
        a.viewer_id = auth.uid()
        and exists (
          select 1 from public.shared_binders b
          where b.id = a.shared_binder_id and b.owner_id = p_friend_id
        )
      )
    );

  delete from public.friendships
  where (user_id = auth.uid() and friend_id = p_friend_id)
     or (user_id = p_friend_id and friend_id = auth.uid());
end;
$$;

create or replace function public.set_shared_binder_friends(
  p_binder_id uuid,
  p_friend_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not exists (
    select 1 from public.shared_binders b
    where b.id = p_binder_id and b.owner_id = auth.uid()
  ) then
    raise exception 'NOT_OWNER';
  end if;

  delete from public.shared_binder_access a
  where a.shared_binder_id = p_binder_id
    and a.source = 'friend'
    and not (a.viewer_id = any(coalesce(p_friend_ids, '{}'::uuid[])));

  insert into public.shared_binder_access(shared_binder_id, viewer_id, source)
  select p_binder_id, f.friend_id, 'friend'
  from public.friendships f
  where f.user_id = auth.uid()
    and f.friend_id = any(coalesce(p_friend_ids, '{}'::uuid[]))
  on conflict (shared_binder_id, viewer_id) do nothing;
end;
$$;
