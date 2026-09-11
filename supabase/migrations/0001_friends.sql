-- Milepost friends layer: a unique username per account, mutual friendships,
-- the stats of activities a user shares with friends, blocks and reports.
--
-- Deliberately NOT here: routes. A shared activity is sport, title, start
-- time, distance and moving time. Where a run starts and ends is where
-- someone lives, so the GPS track never leaves the phone.
--
-- Apply through the management API (project pmdcwgsxxyagmkkypvma):
--   POST https://api.supabase.com/v1/projects/pmdcwgsxxyagmkkypvma/database/query
-- with a non-default User-Agent (Cloudflare 403s urllib), then
-- scripts/e2e_backend.py must pass.

-- ---------------------------------------------------------------- profiles
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name text not null default '' check (char_length(display_name) <= 40),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- ------------------------------------------------------------- friendships
-- One row per pair, whichever side asked. Pending until the addressee
-- accepts; declining or unfriending deletes the row. All writes go through
-- the RPCs below, so the table itself is read-only to clients.
create table if not exists public.friendships (
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create unique index if not exists friendships_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index if not exists friendships_addressee_idx on public.friendships (addressee_id);
alter table public.friendships enable row level security;

create policy friendships_read_own on public.friendships for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- A profile is visible to its owner and to anyone it shares a friendship row
-- with (either status), so request lists and the feed can show names. Finding
-- a stranger goes through search_profiles(), which returns only a handful of
-- rows per query; the table itself cannot be listed.
create policy profiles_read on public.profiles for select to authenticated using (
  id = auth.uid()
  or exists (
    select 1 from public.friendships f
    where (f.requester_id = auth.uid() and f.addressee_id = profiles.id)
       or (f.addressee_id = auth.uid() and f.requester_id = profiles.id)
  )
);
create policy profiles_insert_own on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ------------------------------------------------------- shared activities
-- Keyed by (owner, the phone's own Activity.id) so a re-upload is an upsert
-- and no user's id can ever collide with, or claim, another user's row.
create table if not exists public.shared_activities (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  id uuid not null,
  sport text not null check (sport in ('run', 'walk', 'bike')),
  title text not null check (char_length(title) between 1 and 80),
  start_date timestamptz not null,
  distance_m double precision not null check (distance_m >= 0 and distance_m < 1000000),
  moving_s double precision not null check (moving_s >= 0 and moving_s < 604800),
  created_at timestamptz not null default now(),
  primary key (user_id, id)
);
create index if not exists shared_activities_recent_idx
  on public.shared_activities (user_id, start_date desc);
alter table public.shared_activities enable row level security;

create policy shared_activities_read on public.shared_activities for select to authenticated using (
  user_id = auth.uid()
  or exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = auth.uid() and f.addressee_id = shared_activities.user_id)
        or (f.addressee_id = auth.uid() and f.requester_id = shared_activities.user_id))
  )
);
create policy shared_activities_insert_own on public.shared_activities for insert to authenticated
  with check (user_id = auth.uid());
create policy shared_activities_update_own on public.shared_activities for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy shared_activities_delete_own on public.shared_activities for delete to authenticated
  using (user_id = auth.uid());

-- ------------------------------------------------------------------ blocks
-- Written by block_user(), which also ends any friendship. A block is visible
-- only to the person who made it.
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
alter table public.blocks enable row level security;

create policy blocks_read_own on public.blocks for select to authenticated
  using (blocker_id = auth.uid());
create policy blocks_delete_own on public.blocks for delete to authenticated
  using (blocker_id = auth.uid());

-- ----------------------------------------------------------------- reports
-- App Review guideline 1.2: a way to flag a user or what they posted.
-- Write-only for clients; reviewed from the dashboard.
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  activity_id uuid,
  reason text not null check (char_length(reason) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;

create policy reports_insert_own on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and target_id <> auth.uid());

-- --------------------------------------------------------------- functions
-- Every function reads the caller from auth.uid(); none takes a user id it
-- would have to trust.

-- Username prefix search. SECURITY DEFINER because the caller cannot see
-- strangers' profiles through RLS. Two characters minimum, 20 rows maximum,
-- and people who blocked the caller (or whom the caller blocked) never appear.
create or replace function public.search_profiles(q text)
returns table (id uuid, username text, display_name text, status text)
language sql stable security definer set search_path = public as $$
  with needle as (
    select lower(trim(coalesce(q, ''))) as n
  )
  select p.id, p.username, p.display_name,
         coalesce((
           select case when f.status = 'accepted' then 'friend'
                       when f.requester_id = auth.uid() then 'outgoing'
                       else 'incoming' end
             from public.friendships f
            where (f.requester_id = auth.uid() and f.addressee_id = p.id)
               or (f.addressee_id = auth.uid() and f.requester_id = p.id)
         ), 'none')
    from public.profiles p, needle
   where auth.uid() is not null
     and char_length(needle.n) >= 2
     and p.id <> auth.uid()
     -- Usernames contain underscores, which LIKE reads as a wildcard.
     and p.username like replace(replace(replace(needle.n, '\', '\\'), '%', '\%'), '_', '\_') || '%'
     and not exists (
       select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = auth.uid())
     )
   order by (p.username = needle.n) desc, p.username
   limit 20;
$$;

-- Send a request, or accept one if the other person already asked.
-- Returns the resulting status: 'outgoing' or 'friend'.
create or replace function public.send_friend_request(target uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  existing public.friendships;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if target is null or target = me then raise exception 'you cannot add yourself'; end if;
  if not exists (select 1 from public.profiles where id = me) then
    raise exception 'pick a username first';
  end if;
  -- A block in either direction looks exactly like a missing user.
  if not exists (select 1 from public.profiles where id = target)
     or exists (select 1 from public.blocks b
                 where (b.blocker_id = me and b.blocked_id = target)
                    or (b.blocker_id = target and b.blocked_id = me)) then
    raise exception 'user not found';
  end if;

  select * into existing from public.friendships f
   where (f.requester_id = me and f.addressee_id = target)
      or (f.requester_id = target and f.addressee_id = me);
  if found then
    if existing.status = 'pending' and existing.addressee_id = me then
      update public.friendships set status = 'accepted', accepted_at = now()
       where requester_id = target and addressee_id = me;
      return 'friend';
    end if;
    return case when existing.status = 'accepted' then 'friend' else 'outgoing' end;
  end if;

  if (select count(*) from public.friendships
       where requester_id = me and status = 'pending') >= 100 then
    raise exception 'too many pending requests';
  end if;
  insert into public.friendships (requester_id, addressee_id) values (me, target);
  return 'outgoing';
end $$;

create or replace function public.respond_friend_request(requester uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if accept then
    update public.friendships set status = 'accepted', accepted_at = now()
     where requester_id = requester and addressee_id = me and status = 'pending';
  else
    delete from public.friendships
     where requester_id = requester and addressee_id = me and status = 'pending';
  end if;
end $$;

-- Unfriend, or withdraw a request the caller sent.
create or replace function public.remove_friend(other uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  delete from public.friendships
   where (requester_id = me and addressee_id = other)
      or (requester_id = other and addressee_id = me);
end $$;

create or replace function public.block_user(target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if target is null or target = me then raise exception 'you cannot block yourself'; end if;
  insert into public.blocks (blocker_id, blocked_id) values (me, target)
    on conflict do nothing;
  delete from public.friendships
   where (requester_id = me and addressee_id = target)
      or (requester_id = target and addressee_id = me);
end $$;

-- The people the caller blocked, with names (their profiles are no longer
-- visible through RLS once the friendship is gone).
create or replace function public.list_blocked()
returns table (id uuid, username text, display_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name
    from public.blocks b join public.profiles p on p.id = b.blocked_id
   where b.blocker_id = auth.uid()
   order by p.username;
$$;

-- Friends, incoming and outgoing requests. SECURITY INVOKER: RLS on
-- friendships and profiles already limits this to the caller's own rows.
create or replace function public.list_connections()
returns table (id uuid, username text, display_name text, status text, since timestamptz)
language sql stable set search_path = public as $$
  select p.id, p.username, p.display_name,
         case when f.status = 'accepted' then 'friend'
              when f.requester_id = auth.uid() then 'outgoing'
              else 'incoming' end,
         coalesce(f.accepted_at, f.created_at)
    from public.friendships f
    join public.profiles p
      on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
   where f.requester_id = auth.uid() or f.addressee_id = auth.uid()
   order by 4, 2;
$$;

-- Friends' activities, newest first. SECURITY INVOKER on purpose: the
-- shared_activities read policy is the one place that decides who sees what.
create or replace function public.friend_feed(before_ts timestamptz default null, max_rows int default 50)
returns table (user_id uuid, id uuid, sport text, title text, start_date timestamptz,
               distance_m double precision, moving_s double precision,
               username text, display_name text)
language sql stable set search_path = public as $$
  select a.user_id, a.id, a.sport, a.title, a.start_date, a.distance_m, a.moving_s,
         p.username, p.display_name
    from public.shared_activities a
    join public.profiles p on p.id = a.user_id
   where a.user_id <> auth.uid()
     and (before_ts is null or a.start_date < before_ts)
   order by a.start_date desc
   limit least(greatest(coalesce(max_rows, 50), 1), 100);
$$;

-- App Store 5.1.1(v). No Storage bucket exists, so the auth.users cascade
-- is the whole job.
create or replace function public.delete_account()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;
  delete from auth.users where id = uid;
end $$;

-- Supabase grants EXECUTE on new functions to anon and authenticated by
-- name, and to PUBLIC implicitly; revoking only one half leaves the other.
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.search_profiles(text)',
    'public.send_friend_request(uuid)',
    'public.respond_friend_request(uuid, boolean)',
    'public.remove_friend(uuid)',
    'public.block_user(uuid)',
    'public.list_blocked()',
    'public.list_connections()',
    'public.friend_feed(timestamptz, int)',
    'public.delete_account()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;

-- ------------------------------------------------------------------ grants
-- Start from nothing for clients, then grant exactly what the app uses.
-- anon keeps SELECT (every policy is `to authenticated`, so it reads zero
-- rows) so a session-refresh race reads empty instead of a hard 42501.
revoke all on public.profiles, public.friendships, public.shared_activities,
              public.blocks, public.reports from anon, authenticated;
grant usage on schema public to anon, authenticated, service_role;
grant select on public.profiles, public.friendships, public.shared_activities,
                public.blocks to anon;
grant select, insert on public.profiles to authenticated;
grant update (username, display_name) on public.profiles to authenticated;
grant select on public.friendships to authenticated;
grant select, insert, update, delete on public.shared_activities to authenticated;
grant select, delete on public.blocks to authenticated;
grant insert on public.reports to authenticated;
grant all on all tables in schema public to service_role;

-- Supabase's default privileges hand anon write access, and everyone
-- TRUNCATE (which RLS never sees), on every future table. Take that back.
alter default privileges in schema public revoke insert, update, delete, truncate, trigger, references on tables from anon;
alter default privileges in schema public revoke truncate, trigger, references on tables from authenticated;
alter default privileges for role postgres in schema public revoke insert, update, delete, truncate, trigger, references on tables from anon;
alter default privileges for role postgres in schema public revoke truncate, trigger, references on tables from authenticated;

notify pgrst, 'reload schema';
