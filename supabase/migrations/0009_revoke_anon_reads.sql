-- Revoke the anon role's table grants (security audit 2026-10-07, L3).
-- Every read policy is `to authenticated`, so anon already read zero rows,
-- but a grant is one policy mistake away from a leak: the app never talks
-- to the database without a Sign in with Apple session. anon keeps nothing
-- in public. Default privileges for future tables/functions made by
-- postgres in public no longer include anon either, so a new table starts
-- closed (each migration grants authenticated explicitly, as before).
begin;
revoke all on public.profiles, public.friendships, public.blocks,
              public.shared_activities, public.shared_streets
  from anon;
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
commit;
notify pgrst, 'reload schema';
