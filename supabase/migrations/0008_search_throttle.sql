-- search_profiles hardening (security audit 2026-10-07, L2).
-- Was: 2-character prefixes, 20 rows a call, no limit on calls, so a valid
-- session could page through every username ("aa".."zz" = 676 calls).
-- Now: 3 characters minimum (usernames are 3-20, so an exact username of
-- any legal length still works), and 60 searches per caller per rolling
-- 10 minutes. The app debounces typing (300 ms) and sends nothing under 3
-- characters, so a person never meets the limit; it raises a readable
-- error when they do.
begin;

create table if not exists public.search_quota (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null default now(),
  calls int not null default 0
);
alter table public.search_quota enable row level security;
-- No policies: only the definer function below touches it.
revoke all on public.search_quota from public, anon, authenticated;
grant all on public.search_quota to service_role;

drop function if exists public.search_profiles(text);
create function public.search_profiles(q text)
returns table (id uuid, username text, display_name text, status text)
language plpgsql volatile security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  n text := lower(trim(coalesce(q, '')));
  used int;
begin
  if me is null or char_length(n) < 3 then
    return;
  end if;

  insert into public.search_quota as s (user_id, window_start, calls)
  values (me, now(), 1)
  on conflict (user_id) do update
     set window_start = case when s.window_start < now() - interval '10 minutes' then now() else s.window_start end,
         calls = case when s.window_start < now() - interval '10 minutes' then 1 else s.calls + 1 end
  returning calls into used;
  if used > 60 then
    raise exception 'Too many searches. Try again in a few minutes.' using errcode = 'P0001';
  end if;

  return query
  select p.id, p.username, p.display_name,
         coalesce((
           select case when f.status = 'accepted' then 'friend'
                       when f.requester_id = me then 'outgoing'
                       else 'incoming' end
             from public.friendships f
            where (f.requester_id = me and f.addressee_id = p.id)
               or (f.addressee_id = me and f.requester_id = p.id)
         ), 'none')::text
    from public.profiles p
   where p.id <> me
     -- Usernames contain underscores, which LIKE reads as a wildcard.
     and p.username like replace(replace(replace(n, '\', '\\'), '%', '\%'), '_', '\_') || '%'
     and not exists (
       select 1 from public.blocks b
        where (b.blocker_id = me and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = me)
     )
   order by (p.username = n) desc, p.username
   limit 20;
end $$;
revoke all on function public.search_profiles(text) from public, anon, authenticated;
grant execute on function public.search_profiles(text) to authenticated;

commit;
notify pgrst, 'reload schema';
