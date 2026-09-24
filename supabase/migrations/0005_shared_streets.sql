-- Streets a friend has covered, for the blue/green layer on the Record map
-- (2026-09-24). Opt-in on the phone and OFF by default: until then the app
-- promised friends stats only.
--
-- What is stored is deliberately not a route: the 15 m grid cells an
-- activity crossed (RouteHeatmap.cell packed as x<<32 | y), with the first
-- and last 200 m trimmed off on the phone so where a run starts and ends —
-- usually home — never leaves it. No timestamps, speeds or altitude. The
-- row belongs to a shared activity and dies with it, so turning stats
-- sharing off, deleting the activity, or deleting the account removes it.
begin;

create table if not exists public.shared_streets (
  user_id uuid not null default auth.uid(),
  activity_id uuid not null,
  start_date timestamptz not null,
  -- ~6,700 cells is a 100 km ride; 20,000 bounds a hostile client.
  cells bigint[] not null check (cardinality(cells) between 1 and 20000),
  created_at timestamptz not null default now(),
  primary key (user_id, activity_id),
  foreign key (user_id, activity_id)
    references public.shared_activities (user_id, id) on delete cascade
);
create index if not exists shared_streets_recent_idx
  on public.shared_streets (user_id, start_date desc);
alter table public.shared_streets enable row level security;

-- The same rule as shared_activities: yourself or an accepted friend. A
-- block ends the friendship, which ends this too.
create policy shared_streets_read on public.shared_streets for select to authenticated using (
  user_id = auth.uid()
  or exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = auth.uid() and f.addressee_id = shared_streets.user_id)
        or (f.addressee_id = auth.uid() and f.requester_id = shared_streets.user_id))
  )
);
create policy shared_streets_insert_own on public.shared_streets for insert to authenticated
  with check (user_id = auth.uid());
create policy shared_streets_update_own on public.shared_streets for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy shared_streets_delete_own on public.shared_streets for delete to authenticated
  using (user_id = auth.uid());

-- Friends' streets since a date, newest first. SECURITY INVOKER: the read
-- policy above decides who sees what.
create or replace function public.friend_streets(since_ts timestamptz, max_rows int default 300)
returns table (user_id uuid, activity_id uuid, start_date timestamptz, cells bigint[])
language sql stable set search_path = public as $$
  select s.user_id, s.activity_id, s.start_date, s.cells
    from public.shared_streets s
   where s.user_id <> auth.uid()
     and (since_ts is null or s.start_date >= since_ts)
   order by s.start_date desc
   limit least(greatest(coalesce(max_rows, 300), 1), 300);
$$;
revoke all on function public.friend_streets(timestamptz, int) from public, anon, authenticated;
grant execute on function public.friend_streets(timestamptz, int) to authenticated;

revoke all on public.shared_streets from anon, authenticated;
grant select on public.shared_streets to anon;
grant select, insert, update, delete on public.shared_streets to authenticated;
grant all on public.shared_streets to service_role;

commit;
notify pgrst, 'reload schema';
