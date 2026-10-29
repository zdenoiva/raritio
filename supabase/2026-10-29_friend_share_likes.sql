-- 0.3.8: direct sharing to selected friends + likes on shared cards.

alter table public.shared_binder_access
  add column if not exists source text not null default 'link';

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
    and a.viewer_id in (
      select f.friend_id from public.friendships f where f.user_id = auth.uid()
    );

  insert into public.shared_binder_access(shared_binder_id, viewer_id, source)
  select p_binder_id, f.friend_id, 'friend'
  from public.friendships f
  where f.user_id = auth.uid()
    and f.friend_id = any(coalesce(p_friend_ids, '{}'::uuid[]))
  on conflict (shared_binder_id, viewer_id) do nothing;
end;
$$;

create or replace function public.get_shared_binder_friend_ids(p_binder_id uuid)
returns table(friend_id uuid)
language sql
security definer
set search_path = public
as $$
  select a.viewer_id
  from public.shared_binder_access a
  where a.shared_binder_id = p_binder_id
    and a.source = 'friend'
    and exists (
      select 1 from public.shared_binders b
      where b.id = p_binder_id and b.owner_id = auth.uid()
    );
$$;

create table if not exists public.shared_card_likes (
  shared_binder_id uuid not null references public.shared_binders(id) on delete cascade,
  card_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (shared_binder_id, card_id, user_id)
);

alter table public.shared_card_likes enable row level security;

create or replace function public.get_shared_binder_likes(p_binder_id uuid)
returns table(card_id text, like_count bigint, liked_by_me boolean)
language sql
security definer
set search_path = public
as $$
  select
    l.card_id,
    count(*)::bigint as like_count,
    coalesce(bool_or(l.user_id = auth.uid()), false) as liked_by_me
  from public.shared_card_likes l
  where l.shared_binder_id = p_binder_id
    and exists (
      select 1 from public.shared_binders b
      where b.id = p_binder_id
        and b.is_active
        and (
          b.owner_id = auth.uid()
          or exists (
            select 1 from public.shared_binder_access a
            where a.shared_binder_id = b.id and a.viewer_id = auth.uid()
          )
        )
    )
  group by l.card_id;
$$;

create or replace function public.toggle_card_like(
  p_binder_id uuid,
  p_card_id text
)
returns table(card_id text, like_count bigint, liked_by_me boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer uuid := auth.uid();
  has_access boolean;
begin
  if viewer is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_card_id is null or trim(p_card_id) = '' then
    raise exception 'CARD_REQUIRED';
  end if;

  select exists (
    select 1 from public.shared_binders b
    where b.id = p_binder_id
      and b.is_active
      and (
        b.owner_id = viewer
        or exists (
          select 1 from public.shared_binder_access a
          where a.shared_binder_id = b.id and a.viewer_id = viewer
        )
      )
  ) into has_access;

  if not has_access then
    raise exception 'NO_ACCESS';
  end if;

  if exists (
    select 1 from public.shared_card_likes l
    where l.shared_binder_id = p_binder_id
      and l.card_id = p_card_id
      and l.user_id = viewer
  ) then
    delete from public.shared_card_likes l
    where l.shared_binder_id = p_binder_id
      and l.card_id = p_card_id
      and l.user_id = viewer;
  else
    insert into public.shared_card_likes(shared_binder_id, card_id, user_id)
    values (p_binder_id, p_card_id, viewer)
    on conflict do nothing;
  end if;

  return query
  select
    p_card_id,
    count(*)::bigint,
    coalesce(bool_or(l.user_id = viewer), false)
  from public.shared_card_likes l
  where l.shared_binder_id = p_binder_id and l.card_id = p_card_id;
end;
$$;

create or replace function public.prune_shared_card_likes(
  p_binder_id uuid,
  p_card_ids text[]
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

  delete from public.shared_card_likes l
  where l.shared_binder_id = p_binder_id
    and not (l.card_id = any(coalesce(p_card_ids, '{}'::text[])));
end;
$$;

grant execute on function public.set_shared_binder_friends(uuid, uuid[]) to authenticated;
grant execute on function public.get_shared_binder_friend_ids(uuid) to authenticated;
grant execute on function public.get_shared_binder_likes(uuid) to authenticated;
grant execute on function public.toggle_card_like(uuid, text) to authenticated;
grant execute on function public.prune_shared_card_likes(uuid, text[]) to authenticated;

revoke all on public.shared_card_likes from anon, authenticated;
