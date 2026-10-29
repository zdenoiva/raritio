-- Raritio — Supabase schema for shared binders, friends and keepalive.
-- Run this once in the Supabase SQL Editor.

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default 'Raritio hráč',
  friend_code text not null unique,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

  select * into target
  from public.profiles
  where upper(trim(friend_code)) = upper(trim(p_code))
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
  created_at timestamptz not null default now(),
  primary key (shared_binder_id, viewer_id)
);

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

drop policy if exists "shared_access_owner_select" on public.shared_binder_access;
create policy "shared_access_owner_select" on public.shared_binder_access
  for select using (
    exists (
      select 1 from public.shared_binders b
      where b.id = shared_binder_id and b.owner_id = auth.uid()
    )
  );

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
grant select, insert, update, delete on public.shared_binders to authenticated;
grant select on public.shared_binder_access to authenticated;
grant select on public.keepalive to anon, authenticated;

revoke all on public.friendships from anon, authenticated;

grant execute on function public.add_friend_by_code(text) to authenticated;
grant execute on function public.get_friends() to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.accept_shared_binder(text) to authenticated;
