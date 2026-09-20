-- Nuvo Phase 2.3 — admin controls + safe stock corrections
-- Run after operations-migration.sql.

create or replace function public.adjust_stock(
  p_batch uuid,p_delta integer,p_reason text
) returns uuid language plpgsql security definer set search_path=public as $$
declare b public.batches%rowtype; lid uuid;
begin
  if not public.is_nuvo_admin() then raise exception 'Admin access required'; end if;
  if p_delta=0 then raise exception 'Adjustment cannot be zero'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'A correction reason is required'; end if;
  select * into b from public.batches where id=p_batch for update;
  if not found then raise exception 'Batch not found'; end if;
  if b.qty+p_delta < b.allocated then raise exception 'Correction would reduce stock below already shipped quantity'; end if;
  update public.batches set qty=qty+p_delta where id=p_batch;
  insert into public.inventory_ledger(project_id,batch_id,component,movement,qty,reason,created_by)
  values(b.project_id,b.id,b.type,'ADJUSTMENT',p_delta,p_reason,auth.uid()) returning id into lid;
  insert into public.activity_log(project_id,event,metadata,created_by)
  values(b.project_id,'Stock corrected — '||b.code||' '||case when p_delta>0 then '+' else '' end||p_delta,
    jsonb_build_object('batch_id',b.id,'delta',p_delta,'reason',p_reason),auth.uid());
  return lid;
end $$;
grant execute on function public.adjust_stock(uuid,integer,text) to authenticated;

-- Restrict management tables/actions to admins while Production keeps operational creation.
drop policy if exists "nuvo approved access" on public.projects;
create policy "projects read approved" on public.projects for select to authenticated using(public.is_nuvo_approved());
create policy "projects admin insert" on public.projects for insert to authenticated with check(public.is_nuvo_admin());
create policy "projects admin update" on public.projects for update to authenticated using(public.is_nuvo_admin()) with check(public.is_nuvo_admin());
create policy "projects admin delete" on public.projects for delete to authenticated using(public.is_nuvo_admin());

drop policy if exists "nuvo approved access" on public.target_history;
create policy "target history read approved" on public.target_history for select to authenticated using(public.is_nuvo_approved());
create policy "target history admin insert" on public.target_history for insert to authenticated with check(public.is_nuvo_admin());

-- Batches: approved staff can create/read; only admin may alter existing batch state/quantity.
drop policy if exists "nuvo approved access" on public.batches;
create policy "batches read approved" on public.batches for select to authenticated using(public.is_nuvo_approved());
create policy "batches create approved" on public.batches for insert to authenticated with check(public.is_nuvo_approved());
create policy "batches admin update" on public.batches for update to authenticated using(public.is_nuvo_admin()) with check(public.is_nuvo_admin());

-- Shipment inserts occur only through the atomic RPC; direct modifications are admin-only.
drop policy if exists "nuvo approved access" on public.shipments;
create policy "shipments read approved" on public.shipments for select to authenticated using(public.is_nuvo_approved());
create policy "shipments admin modify" on public.shipments for update to authenticated using(public.is_nuvo_admin()) with check(public.is_nuvo_admin());

-- Ledger is append-only from trusted functions/triggers for clients.
drop policy if exists "nuvo approved access" on public.inventory_ledger;
create policy "ledger read approved" on public.inventory_ledger for select to authenticated using(public.is_nuvo_approved());

-- Notes and activity remain collaborative, but clients cannot rewrite audit history.
drop policy if exists "nuvo approved access" on public.activity_log;
create policy "activity read approved" on public.activity_log for select to authenticated using(public.is_nuvo_approved());
create policy "activity insert approved" on public.activity_log for insert to authenticated with check(public.is_nuvo_approved());
