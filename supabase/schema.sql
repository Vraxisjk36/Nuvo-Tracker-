-- Nuvo Production Tracker — Phase 2 shared backend
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'production' check (role in ('admin','production')),
  created_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  client text not null,
  name text not null,
  location text,
  product text not null,
  production_target_sets integer not null check (production_target_sets > 0),
  delivery_target_sets integer check (delivery_target_sets > 0),
  due date not null,
  priority text not null default 'Normal' check (priority in ('Normal','High','Urgent')),
  base_weight numeric,
  activator_weight numeric,
  dilution numeric not null default 8,
  status text not null default 'In Production',
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.batches (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  type text not null check (type in ('Base','Activator')),
  qty integer not null check (qty > 0),
  epicure numeric not null default 0,
  dilute numeric not null default 0,
  materials jsonb not null default '[]'::jsonb,
  production_date date not null,
  expiry date not null,
  code text not null unique,
  notes text,
  status text not null default 'Available',
  allocated integer not null default 0 check (allocated >= 0),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.shipments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  base_qty integer not null default 0 check (base_qty >= 0),
  activator_qty integer not null default 0 check (activator_qty >= 0),
  shipment_date date not null,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.project_notes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  body text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.target_history (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  old_target integer not null,
  new_target integer not null,
  reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete cascade,
  event text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.batches enable row level security;
alter table public.shipments enable row level security;
alter table public.project_notes enable row level security;
alter table public.target_history enable row level security;
alter table public.activity_log enable row level security;

-- Nuvo is a private two-person workspace: authenticated members may read/write operational data.
-- Role-specific restrictions can be tightened later without changing the frontend data model.
do $$ declare t text; begin
  foreach t in array array['profiles','projects','batches','shipments','project_notes','target_history','activity_log']
  loop
    execute format('drop policy if exists "nuvo authenticated access" on public.%I',t);
    execute format('create policy "nuvo authenticated access" on public.%I for all to authenticated using (true) with check (true)',t);
  end loop;
end $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,display_name,role)
  values(new.id,coalesce(new.raw_user_meta_data->>'display_name',split_part(new.email,'@',1)),'production')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Enable these tables for Realtime in Supabase.
do $$ begin
  alter publication supabase_realtime add table public.projects;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.batches;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.shipments;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.project_notes;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.target_history;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.activity_log;
exception when duplicate_object then null; end $$;
