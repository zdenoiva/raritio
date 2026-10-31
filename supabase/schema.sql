-- Raritio — Supabase schema for shared binders, friends and keepalive.
-- Run this once in the Supabase SQL Editor.

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default 'Raritio hráč',
  friend_code text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles drop column if exists email;

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- Friends
-- ---------------------------------------------------------------------------
create table if not exists public.friendships (
  user_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

alter table public.friendships enable row level security;

drop policy if exists "friendships_select_own" on public.friendships;
create policy "friendships_select_own" on public.friendships
  for select using (auth.uid() = user_id);

drop policy if exists "friendships_delete_own" on public.friendships;
create policy "friendships_delete_own" on public.friendships
  for delete using (auth.uid() = user_id);

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

create or replace function public.get_friends()
returns table(friend_id uuid, nickname text, friend_code text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.nickname, p.friend_code
  from public.friendships f
  join public.profiles p on p.id = f.friend_id
  where f.user_id = auth.uid()
  order by lower(p.nickname);
$$;

create or replace function public.remove_friend(p_friend_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Revoke direct friend access in both directions before removing the
  -- friendship, otherwise an ex-friend keeps access to shared binders.
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

-- ---------------------------------------------------------------------------
-- Shared binders
-- ---------------------------------------------------------------------------
create table if not exists public.shared_binders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  owner_nickname text not null default 'Raritio hráč',
  name text not null,
  snapshot jsonb not null default '{}'::jsonb,
  card_count integer not null default 0,
  total_value numeric not null default 0,
  share_token text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shared_binder_access (
  shared_binder_id uuid not null references public.shared_binders(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  source text not null default 'link',
  created_at timestamptz not null default now(),
  primary key (shared_binder_id, viewer_id)
);

alter table public.shared_binder_access
  add column if not exists source text not null default 'link';

alter table public.shared_binders enable row level security;
alter table public.shared_binder_access enable row level security;

drop policy if exists "shared_binders_owner_all" on public.shared_binders;
create policy "shared_binders_owner_all" on public.shared_binders
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "shared_binders_viewer_select" on public.shared_binders;
create policy "shared_binders_viewer_select" on public.shared_binders
  for select using (
    is_active and exists (
      select 1
      from public.shared_binder_access a
      where a.shared_binder_id = shared_binders.id
        and a.viewer_id = auth.uid()
    )
  );

drop policy if exists "shared_access_viewer_select" on public.shared_binder_access;
create policy "shared_access_viewer_select" on public.shared_binder_access
  for select using (auth.uid() = viewer_id);

-- Owners need their share token, but viewers must never receive it. The
-- share_token column is not granted to authenticated; only these owner-checked
-- security-definer functions expose it.
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

-- The owner policy deliberately does not query shared_binders here: that caused
-- infinite RLS recursion with the viewer policy above. Owners manage sharing
-- through binder actions; they do not need to list access rows in this beta.
drop policy if exists "shared_access_owner_select" on public.shared_binder_access;

create or replace function public.accept_shared_binder(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  binder public.shared_binders;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into binder
  from public.shared_binders
  where share_token = trim(p_token) and is_active = true
  limit 1;

  if not found or binder.id is null then
    raise exception 'SHARE_NOT_FOUND';
  end if;

  if binder.owner_id <> auth.uid() then
    insert into public.shared_binder_access(shared_binder_id, viewer_id)
    values (binder.id, auth.uid())
    on conflict do nothing;
  end if;

  return binder.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Direct friend sharing
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Card likes on shared binders
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Aggregate public statistics (hidden panel)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Account deletion
-- ---------------------------------------------------------------------------
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

  -- Cascades remove profile, friendships, shared binders, access rows,
  -- likes and other auth-owned data.
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------------
-- Keepalive row for the GitHub Actions cron ping
-- ---------------------------------------------------------------------------
create table if not exists public.keepalive (
  id integer primary key default 1,
  last_ping timestamptz not null default now()
);

insert into public.keepalive(id)
values (1)
on conflict (id) do nothing;

alter table public.keepalive enable row level security;

drop policy if exists "keepalive_public_read" on public.keepalive;
create policy "keepalive_public_read" on public.keepalive
  for select using (true);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists shared_binders_touch on public.shared_binders;
create trigger shared_binders_touch
  before update on public.shared_binders
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
revoke select on public.shared_binders from authenticated;
grant select (
  id, owner_id, owner_nickname, name, snapshot, card_count, total_value,
  is_active, created_at, updated_at
) on public.shared_binders to authenticated;
grant insert, update, delete on public.shared_binders to authenticated;
grant select on public.shared_binder_access to authenticated;
grant select on public.keepalive to anon, authenticated;

revoke all on public.friendships from anon, authenticated;
grant select, delete on public.friendships to authenticated;

grant execute on function public.add_friend_by_code(text) to authenticated;
grant execute on function public.get_friends() to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.accept_shared_binder(text) to authenticated;
grant execute on function public.set_shared_binder_friends(uuid, uuid[]) to authenticated;
grant execute on function public.get_shared_binder_friend_ids(uuid) to authenticated;
grant execute on function public.get_shared_binder_likes(uuid) to authenticated;
grant execute on function public.toggle_card_like(uuid, text) to authenticated;
grant execute on function public.prune_shared_card_likes(uuid, text[]) to authenticated;
grant execute on function public.delete_my_account() to authenticated;

revoke all on public.shared_card_likes from anon, authenticated;
