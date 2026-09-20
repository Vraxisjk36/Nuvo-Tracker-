-- Nuvo Phase 2.1 — signup approval security migration
-- Run this once in Supabase SQL Editor after the original schema.

alter table public.profiles
  add column if not exists approved boolean not null default false;

-- Existing users are intentionally NOT auto-approved.
-- Approve the owner/admin explicitly after signup.

create or replace function public.is_nuvo_approved()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles p where p.id=auth.uid() and p.approved=true);
$$;

create or replace function public.is_nuvo_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles p where p.id=auth.uid() and p.approved=true and p.role='admin');
$$;

-- Profiles: users can see themselves; approved admins can see everyone.
drop policy if exists "nuvo authenticated access" on public.profiles;
drop policy if exists "profiles read self or admin" on public.profiles;
drop policy if exists "profiles admin update" on public.profiles;
create policy "profiles read self or admin" on public.profiles
for select to authenticated
using (id=auth.uid() or public.is_nuvo_admin());
create policy "profiles admin update" on public.profiles
for update to authenticated
using (public.is_nuvo_admin())
with check (public.is_nuvo_admin());

-- Operational tables: approved users only.
do $$ declare t text; begin
  foreach t in array array['projects','batches','shipments','project_notes','target_history','activity_log']
  loop
    execute format('drop policy if exists "nuvo authenticated access" on public.%I',t);
    execute format('drop policy if exists "nuvo approved access" on public.%I',t);
    execute format('create policy "nuvo approved access" on public.%I for all to authenticated using (public.is_nuvo_approved()) with check (public.is_nuvo_approved())',t);
  end loop;
end $$;

-- New signups always begin unapproved as Production.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,display_name,role,approved)
  values(new.id,coalesce(new.raw_user_meta_data->>'display_name',split_part(new.email,'@',1)),'production',false)
  on conflict (id) do nothing;
  return new;
end $$;
