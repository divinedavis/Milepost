-- Bound what one session can store in shared_streets. A row is up to
-- 10,000 cells (80 KB); 1,000 rows per account is ~80 MB worst case for a
-- hostile client. The app only ever uploads streets for its most recent
-- 500 activities, so an honest user never meets either limit.
begin;
alter table public.shared_streets drop constraint if exists shared_streets_cells_check;
alter table public.shared_streets
  add constraint shared_streets_cells_check check (cardinality(cells) between 1 and 10000);

create or replace function public.cap_shared_streets()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.shared_streets where user_id = new.user_id) >= 1000 then
    raise exception 'shared streets limit reached';
  end if;
  return new;
end $$;
revoke all on function public.cap_shared_streets() from public, anon, authenticated;

drop trigger if exists shared_streets_cap on public.shared_streets;
create trigger shared_streets_cap before insert on public.shared_streets
  for each row execute function public.cap_shared_streets();
commit;
notify pgrst, 'reload schema';
