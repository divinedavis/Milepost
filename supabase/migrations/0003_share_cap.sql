-- A ceiling on shared activities per account. Nothing else bounds what a
-- client with a valid session can insert, so one script could fill the
-- database (and the bill). 20,000 is decades of daily runs; the app never
-- comes near it, so hitting it means abuse, not a real user.

create or replace function public.cap_shared_activities()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.shared_activities where user_id = new.user_id) >= 20000 then
    raise exception 'shared activity limit reached';
  end if;
  return new;
end $$;
revoke all on function public.cap_shared_activities() from public, anon, authenticated;

drop trigger if exists shared_activities_cap on public.shared_activities;
create trigger shared_activities_cap before insert on public.shared_activities
  for each row execute function public.cap_shared_activities();

-- Same for reports: 200 a day per reporter is far past any honest use.
create or replace function public.cap_reports()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.reports
       where reporter_id = new.reporter_id and created_at > now() - interval '1 day') >= 200 then
    raise exception 'too many reports today';
  end if;
  return new;
end $$;
revoke all on function public.cap_reports() from public, anon, authenticated;

drop trigger if exists reports_cap on public.reports;
create trigger reports_cap before insert on public.reports
  for each row execute function public.cap_reports();

create index if not exists reports_reporter_idx on public.reports (reporter_id, created_at desc);

notify pgrst, 'reload schema';
