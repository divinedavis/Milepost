-- ONE-OFF, applied 2026-10-07 (security audit M1). Do not re-run: it trims
-- again from the already-trimmed ends.
--
-- Until build 32 the phone trimmed the first and last 200 m ALONG the route
-- and uploaded cells in route order with an exact start time, so a loop
-- that came back past the front door shared it, and the order gave away
-- direction. The app now drops every cell within 400 m (a radius) of each
-- start, end and frequent endpoint, sorts the cells, and sends the day only.
--
-- The server has no routes, so the rows already uploaded (9, one user) are
-- re-derived from what it has: under the old rule a row's first and last
-- cells were at most 200 m from the real ends, so every cell within 615 m
-- of ANY row's first or last cell (same user) covers a >=400 m radius round
-- every start and end and the places they repeat. Rows left empty are
-- deleted (1 of 9). Dates are cut to midnight UTC. New builds re-upload
-- under the new rule (social.streetsUploaded.v2), replacing these rows.
begin;
create temp table c on commit drop as
select s.user_id, s.activity_id, ord, v,
       (v >> 32)::int as x, (v & 4294967295)::bigint as ylow
  from public.shared_streets s, unnest(s.cells) with ordinality u(v, ord);
update c set ylow = case when ylow >= 2147483648 then ylow - 4294967296 else ylow end;
-- first and last stored cell of each row: the old rule left them <=200 m from the real ends
create temp table ends on commit drop as
select distinct on (user_id, activity_id, which) user_id, x, ylow
  from (select *, 'first' as which from c union all select *, 'last' from c) t
 order by user_id, activity_id, which, case when which='first' then ord else -ord end;
create temp table keep on commit drop as
select c.user_id, c.activity_id, array_agg(distinct c.v order by c.v) as cells
  from c
 where not exists (select 1 from ends e where e.user_id = c.user_id
                   and 15.0 * sqrt(power(c.x - e.x, 2) + power(c.ylow - e.ylow, 2)) <= 615)
 group by 1, 2;
delete from public.shared_streets s
 where not exists (select 1 from keep k where k.user_id = s.user_id and k.activity_id = s.activity_id);
update public.shared_streets s
   set cells = k.cells,
       start_date = date_trunc('day', s.start_date at time zone 'UTC') at time zone 'UTC'
  from keep k where k.user_id = s.user_id and k.activity_id = s.activity_id;

commit;
notify pgrst, 'reload schema';
