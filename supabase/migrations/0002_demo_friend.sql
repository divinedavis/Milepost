-- The App Review demo friend. A reviewer has one Apple Account and no one to
-- be friends with, so requests sent to an account listed in demo_accounts are
-- accepted on insert. scripts/seed_demo_friend.py creates @milepost_demo,
-- lists it here and gives it sample activities.
--
-- Keyed on the id, never the username: a username check would let whoever
-- registered the name first receive auto-accepted friendships (and see every
-- requester's activities).

create table if not exists public.demo_accounts (
  id uuid primary key references public.profiles(id) on delete cascade
);
alter table public.demo_accounts enable row level security;
-- No policies and no client grants: only the service role writes or reads it.
revoke all on public.demo_accounts from anon, authenticated;
grant all on public.demo_accounts to service_role;

create or replace function public.auto_accept_demo_friend()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.demo_accounts d where d.id = new.addressee_id) then
    new.status := 'accepted';
    new.accepted_at := now();
  end if;
  return new;
end $$;
revoke all on function public.auto_accept_demo_friend() from public, anon, authenticated;

drop trigger if exists friendships_auto_accept_demo on public.friendships;
create trigger friendships_auto_accept_demo before insert on public.friendships
  for each row execute function public.auto_accept_demo_friend();

-- 0001's version returned a literal 'outgoing' after its insert, which the
-- trigger above can make untrue. Report the status the row actually got.
create or replace function public.send_friend_request(target uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  existing public.friendships;
  stored text;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if target is null or target = me then raise exception 'you cannot add yourself'; end if;
  if not exists (select 1 from public.profiles where id = me) then
    raise exception 'pick a username first';
  end if;
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
  insert into public.friendships (requester_id, addressee_id) values (me, target)
    returning status into stored;
  return case when stored = 'accepted' then 'friend' else 'outgoing' end;
end $$;
revoke all on function public.send_friend_request(uuid) from public, anon, authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;

notify pgrst, 'reload schema';
