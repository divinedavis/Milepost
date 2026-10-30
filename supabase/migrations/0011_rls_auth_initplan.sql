-- milepost: wrap auth.*() in (select ...) so RLS evaluates it once per
-- query, not once per row (advisor auth_rls_initplan). Same predicates.
-- Generated from live pg_policies 2026-10-30.

alter policy "friendships_read_own" on public."friendships"
  using (((requester_id = ( SELECT auth.uid() AS uid)) OR (addressee_id = ( SELECT auth.uid() AS uid))));

alter policy "profiles_read" on public."profiles"
  using (((id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM friendships f
  WHERE (((f.requester_id = ( SELECT auth.uid() AS uid)) AND (f.addressee_id = profiles.id)) OR ((f.addressee_id = ( SELECT auth.uid() AS uid)) AND (f.requester_id = profiles.id)))))));

alter policy "profiles_insert_own" on public."profiles"
  with check ((id = ( SELECT auth.uid() AS uid)));

alter policy "profiles_update_own" on public."profiles"
  using ((id = ( SELECT auth.uid() AS uid)))
  with check ((id = ( SELECT auth.uid() AS uid)));

alter policy "shared_activities_read" on public."shared_activities"
  using (((user_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM friendships f
  WHERE ((f.status = 'accepted'::text) AND (((f.requester_id = ( SELECT auth.uid() AS uid)) AND (f.addressee_id = shared_activities.user_id)) OR ((f.addressee_id = ( SELECT auth.uid() AS uid)) AND (f.requester_id = shared_activities.user_id))))))));

alter policy "shared_activities_insert_own" on public."shared_activities"
  with check ((user_id = ( SELECT auth.uid() AS uid)));

alter policy "shared_activities_update_own" on public."shared_activities"
  using ((user_id = ( SELECT auth.uid() AS uid)))
  with check ((user_id = ( SELECT auth.uid() AS uid)));

alter policy "shared_activities_delete_own" on public."shared_activities"
  using ((user_id = ( SELECT auth.uid() AS uid)));

alter policy "blocks_read_own" on public."blocks"
  using ((blocker_id = ( SELECT auth.uid() AS uid)));

alter policy "blocks_delete_own" on public."blocks"
  using ((blocker_id = ( SELECT auth.uid() AS uid)));

alter policy "reports_insert_own" on public."reports"
  with check (((reporter_id = ( SELECT auth.uid() AS uid)) AND (target_id <> ( SELECT auth.uid() AS uid))));

alter policy "shared_streets_read" on public."shared_streets"
  using (((user_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM friendships f
  WHERE ((f.status = 'accepted'::text) AND (((f.requester_id = ( SELECT auth.uid() AS uid)) AND (f.addressee_id = shared_streets.user_id)) OR ((f.addressee_id = ( SELECT auth.uid() AS uid)) AND (f.requester_id = shared_streets.user_id))))))));

alter policy "shared_streets_insert_own" on public."shared_streets"
  with check ((user_id = ( SELECT auth.uid() AS uid)));

alter policy "shared_streets_update_own" on public."shared_streets"
  using ((user_id = ( SELECT auth.uid() AS uid)))
  with check ((user_id = ( SELECT auth.uid() AS uid)));

alter policy "shared_streets_delete_own" on public."shared_streets"
  using ((user_id = ( SELECT auth.uid() AS uid)));
