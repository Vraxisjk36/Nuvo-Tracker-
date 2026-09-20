-- Nuvo Phase 2.2 — inventory ledger, atomic shipping, audit metadata
-- Run once in Supabase SQL Editor after approval-migration.sql.

create table if not exists public.inventory_ledger (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  batch_id uuid references public.batches(id) on delete set null,
  shipment_id uuid references public.shipments(id) on delete set null,
  component text not null check (component in ('Base','Activator')),
  movement text not null check (movement in ('PRODUCTION','SHIPMENT','ADJUSTMENT')),
  qty integer not null check (qty <> 0),
  reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;
drop policy if exists "nuvo approved access" on public.inventory_ledger;
create policy "nuvo approved access" on public.inventory_ledger
for all to authenticated using (public.is_nuvo_approved()) with check (public.is_nuvo_approved());

alter table public.shipments add column if not exists reference text;
alter table public.activity_log add column if not exists metadata jsonb not null default '{}'::jsonb;

create or replace function public.record_nuvo_batch_ledger()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.inventory_ledger(project_id,batch_id,component,movement,qty,reason,created_by)
  values(new.project_id,new.id,new.type,'PRODUCTION',new.qty,'Batch '||new.code||' produced',new.created_by);
  return new;
end $$;
drop trigger if exists nuvo_batch_ledger on public.batches;
create trigger nuvo_batch_ledger after insert on public.batches
for each row execute procedure public.record_nuvo_batch_ledger();

-- Backfill existing batches once, safely.
insert into public.inventory_ledger(project_id,batch_id,component,movement,qty,reason,created_by,created_at)
select b.project_id,b.id,b.type,'PRODUCTION',b.qty,'Batch '||b.code||' produced',b.created_by,b.created_at
from public.batches b
where not exists(select 1 from public.inventory_ledger l where l.batch_id=b.id and l.movement='PRODUCTION');

create or replace function public.record_shipment_atomic(
  p_project uuid,p_base integer,p_activator integer,p_date date,p_notes text,p_reference text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  sid uuid; need integer; r record; take_qty integer;
begin
  if not public.is_nuvo_approved() then raise exception 'Nuvo access not approved'; end if;
  if coalesce(p_base,0)<0 or coalesce(p_activator,0)<0 or (coalesce(p_base,0)=0 and coalesce(p_activator,0)=0) then
    raise exception 'Invalid shipment quantity';
  end if;

  -- Lock project batches so two devices cannot consume the same stock.
  perform 1 from public.batches where project_id=p_project for update;

  if p_base > coalesce((select sum(qty-allocated) from public.batches where project_id=p_project and type='Base' and status not in ('On Hold','Expired') and expiry>=current_date),0)
     or p_activator > coalesce((select sum(qty-allocated) from public.batches where project_id=p_project and type='Activator' and status not in ('On Hold','Expired') and expiry>=current_date),0)
  then raise exception 'Shipment exceeds available valid stock'; end if;

  insert into public.shipments(project_id,base_qty,activator_qty,shipment_date,notes,reference,created_by)
  values(p_project,p_base,p_activator,p_date,p_notes,p_reference,auth.uid()) returning id into sid;

  for r in select * from (values ('Base'::text,p_base),('Activator'::text,p_activator)) v(component,wanted) loop
    need:=r.wanted;
    for r in select id,qty,allocated from public.batches
      where project_id=p_project and type=r.component and status not in ('On Hold','Expired')
        and expiry>=current_date and qty>allocated
      order by expiry,production_date,id for update
    loop
      exit when need<=0;
      take_qty:=least(need,r.qty-r.allocated);
      update public.batches set allocated=allocated+take_qty where id=r.id;
      insert into public.inventory_ledger(project_id,batch_id,shipment_id,component,movement,qty,reason,created_by)
      values(p_project,r.id,sid,(select type from public.batches where id=r.id),'SHIPMENT',-take_qty,coalesce(p_reference,'Shipment'),auth.uid());
      need:=need-take_qty;
    end loop;
  end loop;

  insert into public.activity_log(project_id,event,metadata,created_by)
  values(p_project,'Shipment recorded — '||p_base||' Base / '||p_activator||' Activator',
    jsonb_build_object('shipment_id',sid,'base',p_base,'activator',p_activator,'reference',p_reference),auth.uid());
  return sid;
end $$;
grant execute on function public.record_shipment_atomic(uuid,integer,integer,date,text,text) to authenticated;

do $$ begin alter publication supabase_realtime add table public.inventory_ledger;
exception when duplicate_object then null; end $$;
