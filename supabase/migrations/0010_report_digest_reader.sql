-- Daily email of new reports (security audit 2026-10-07, L4). Until now
-- public.reports had no alerting; CLAUDE.md said "check the table before
-- each release".
--
-- The mailer is a cron on the divinedavis.com droplet (104.236.120.144,
-- /usr/local/bin/milepost-report-digest, see scripts/report_digest.py),
-- sending through the uptime-watch SMTP account already there: no new
-- service, nothing that bills. It logs in through the session pooler as
-- its own role that can read ONE view and nothing else — no service-role
-- key on the droplet. The role's password is set out of band (never in
-- git) and lives in /etc/milepost-report-digest.env (0600, root).
--
-- The view is in schema `ops`, which PostgREST does not expose, and is
-- revoked from anon/authenticated (default privileges would otherwise
-- hand authenticated every report).
begin;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'milepost_report_digest') then
    create role milepost_report_digest login noinherit nocreatedb nocreaterole;
  end if;
end $$;
alter role milepost_report_digest set statement_timeout = '15s';
alter role milepost_report_digest connection limit 2;

create schema if not exists ops;
revoke all on schema ops from public, anon, authenticated;
grant usage on schema ops to milepost_report_digest;

create or replace view ops.report_digest as
select r.id, r.created_at, r.reason, r.activity_id,
       rp.username as reporter, tp.username as target, r.target_id,
       (select count(*) from public.reports x where x.target_id = r.target_id) as target_total
  from public.reports r
  left join public.profiles rp on rp.id = r.reporter_id
  left join public.profiles tp on tp.id = r.target_id;
revoke all on ops.report_digest from public, anon, authenticated;
grant select on ops.report_digest to milepost_report_digest;
commit;
