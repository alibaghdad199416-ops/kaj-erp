begin;

create or replace function public.erp_r37_cloud_command(
  p_area text,p_action text,p_payload jsonb
) returns jsonb
language sql security definer set search_path=public
as $$ select public.erp_r35_cloud_command($1,$2,coalesce($3,'{}'::jsonb)) $$;
revoke all on function public.erp_r37_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r37_cloud_command(text,text,jsonb) to authenticated,service_role;

create or replace function public.erp_r37_advance_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype;
begin
  perform public.erp_advance_cloud_maintenance_workflow(p_company_id,p_order_id);
  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then raise exception 'maintenance_order_not_found' using errcode='P0001'; end if;
  return jsonb_build_object(
    'ok',true,'orderId',o.id,'orderNumber',o.order_number,
    'workflowStage',o.workflow_stage,'status',o.status,
    'stockIssueNumber',o.stock_issue_number,'invoiceNumber',o.invoice_number,
    'updatedAt',o.updated_at
  );
end $$;
revoke all on function public.erp_r37_advance_maintenance_workflow(uuid,uuid) from public,anon;
grant execute on function public.erp_r37_advance_maintenance_workflow(uuid,uuid) to authenticated,service_role;

-- Recover opportunity links from either side of the relationship. Historical
-- opportunity records can contain saleId/salesOrderId even when the normalized
-- sales order opportunity_id was not persisted.
create or replace function public.erp_r37_reconcile_opportunity_sales_links(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_slug text; r record; v_backfilled int:=0; v_synced int:=0;
begin
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then raise exception 'company_not_found' using errcode='23503'; end if;

  for r in
    select record_id,
           nullif(btrim(coalesce(payload->>'salesOrderId',payload->>'saleId','')),'') order_id
    from public.erp_records
    where company_id=v_slug and entity_type='opportunities' and deleted_at is null
      and nullif(btrim(coalesce(payload->>'salesOrderId',payload->>'saleId','')),'') is not null
  loop
    if r.order_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       and exists(select 1 from public.erp_sales_orders_cloud o where o.company_id=p_company_id and o.id=r.order_id::uuid and not o.is_deleted)
       and not exists(select 1 from public.erp_sales_orders_cloud o where o.company_id=p_company_id and o.opportunity_id=r.record_id and o.id<>r.order_id::uuid and not o.is_deleted)
    then
      update public.erp_sales_orders_cloud
         set opportunity_id=r.record_id,updated_at=now(),updated_by=auth.uid()
       where company_id=p_company_id and id=r.order_id::uuid and not is_deleted
         and opportunity_id is distinct from r.record_id;
      if found then v_backfilled:=v_backfilled+1; end if;
    end if;
  end loop;

  for r in select distinct opportunity_id
    from public.erp_sales_orders_cloud
    where company_id=p_company_id and not is_deleted
      and nullif(btrim(coalesce(opportunity_id,'')),'') is not null
  loop
    perform public.erp_sync_opportunity_sales_lifecycle(p_company_id,r.opportunity_id);
    v_synced:=v_synced+1;
  end loop;
  return jsonb_build_object('ok',true,'backfilledOrders',v_backfilled,'syncedOpportunities',v_synced);
end $$;
revoke all on function public.erp_r37_reconcile_opportunity_sales_links(uuid) from public,anon;
grant execute on function public.erp_r37_reconcile_opportunity_sales_links(uuid) to authenticated,service_role;

create or replace function public.erp_r37_opportunity_record_link_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_company uuid;
begin
  if pg_trigger_depth()>1 or new.entity_type<>'opportunities' or new.deleted_at is not null then return new; end if;
  select id into v_company from public.companies where slug=new.company_id;
  if v_company is not null then perform public.erp_r37_reconcile_opportunity_sales_links(v_company); end if;
  return new;
end $$;
drop trigger if exists trg_r37_opportunity_record_link on public.erp_records;
create trigger trg_r37_opportunity_record_link
after insert or update of payload,deleted_at on public.erp_records
for each row execute function public.erp_r37_opportunity_record_link_trigger();

create or replace function public.erp_r37_sales_order_opportunity_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if pg_trigger_depth()>1 then return new; end if;
  if nullif(btrim(coalesce(new.opportunity_id,'')),'') is not null then
    perform public.erp_sync_opportunity_sales_lifecycle(new.company_id,new.opportunity_id);
  end if;
  return new;
end $$;
drop trigger if exists trg_r37_sales_order_opportunity on public.erp_sales_orders_cloud;
create trigger trg_r37_sales_order_opportunity
after insert or update of opportunity_id,status,is_deleted on public.erp_sales_orders_cloud
for each row execute function public.erp_r37_sales_order_opportunity_trigger();

-- Reconcile current active records immediately.
do $$ declare c record; begin
  for c in select id from public.companies loop
    perform public.erp_r37_reconcile_opportunity_sales_links(c.id);
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
