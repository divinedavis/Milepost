-- Allow stroller runs to retain their activity type in the friends feed.
begin;
alter table public.shared_activities
  drop constraint shared_activities_sport_check;
alter table public.shared_activities
  add constraint shared_activities_sport_check
  check (sport in ('run', 'strollerRun', 'walk', 'bike'));
commit;
