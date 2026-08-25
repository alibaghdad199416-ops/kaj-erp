begin;

-- R27: stable PostgREST command endpoint. Keep one explicit signature.
do $$
declare r regprocedure;
begin
  for r in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='erp_r27_cloud_command'
  loop execute format('drop function %s', r); end loop;
end $$;

create function public.erp_r27_cloud_command(p_area text,p_action text,p_payload jsonb)
returns jsonb
language sql
security definer
set search_path=public
as $$
  select public.erp_r14_phase26_cloud_command($1,$2,coalesce($3,'{}'::jsonb))
$$;
revoke all on function public.erp_r27_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r27_cloud_command(text,text,jsonb) to authenticated,service_role;

-- Canonical cashbox read path: one ledger id only. The snake/camel aliases are
-- emitted from the same authoritative value so a legacy alias cannot reappear
-- after reload.
create or replace function public.erp_r27_list_cash_accounts(p_company_id uuid)
returns setof jsonb
language sql stable security definer set search_path=public
as $$
  select ca.data
    || jsonb_build_object(
      'id',ca.id,
      'accountId',public.erp_r23_cashbox_ledger_account_id(ca.data),
      'account_id',public.erp_r23_cashbox_ledger_account_id(ca.data),
      'updatedAt',ca.updated_at,
      'updated_at',ca.updated_at,
      '_cloudCreatedAt',ca.created_at,
      '_cloudUpdatedAt',ca.updated_at,
      '_cloudVersion',ca.version,
      'ledgerAccountCode',a.code,
      'ledgerAccountName',a.name,
      'ledgerAccountCurrency',a.currency
    )
  from public.erp_cash_accounts ca
  left join public.erp_accounts a
    on a.organization_id=ca.company_id
   and a.account_id=public.erp_r23_cashbox_ledger_account_id(ca.data)
  where ca.company_id=p_company_id
    and not ca.is_deleted
    and public.erp_is_company_member(p_company_id)
  order by public.erp_try_boolean(coalesce(ca.data->>'isActive',ca.data->>'is_active'),'true') desc,
           lower(coalesce(ca.data->>'name','')),ca.id
$$;
revoke all on function public.erp_r27_list_cash_accounts(uuid) from public,anon;
grant execute on function public.erp_r27_list_cash_accounts(uuid) to authenticated,service_role;

create or replace function public.erp_r27_save_cash_account(p_company_id uuid,p_account jsonb)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_payload jsonb:=coalesce(p_account,'{}'::jsonb);
  v_id text:=btrim(coalesce(v_payload->>'id',''));
  v_ledger text;
  v_saved jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied' using errcode='42501'; end if;
  if v_id='' then raise exception 'cashbox_id_required'; end if;
  -- The value sent by the current form wins. New cloud forms send account_id.
  v_ledger:=nullif(btrim(coalesce(nullif(v_payload->>'account_id',''),nullif(v_payload->>'accountId',''))),'');
  if v_ledger is null then raise exception 'cashbox_ledger_account_required'; end if;
  v_payload:=v_payload||jsonb_build_object('accountId',v_ledger,'account_id',v_ledger);
  perform public.erp_save_cloud_cash_account(p_company_id,v_payload);
  select ca.data||jsonb_build_object(
      'id',ca.id,'accountId',v_ledger,'account_id',v_ledger,
      '_cloudCreatedAt',ca.created_at,'_cloudUpdatedAt',ca.updated_at,'_cloudVersion',ca.version)
    into v_saved
  from public.erp_cash_accounts ca where ca.company_id=p_company_id and ca.id=v_id and not ca.is_deleted;
  return coalesce(v_saved,'{}'::jsonb);
end $$;
revoke all on function public.erp_r27_save_cash_account(uuid,jsonb) from public,anon;
grant execute on function public.erp_r27_save_cash_account(uuid,jsonb) to authenticated,service_role;

-- Canonical inventory movement log. It exposes the commercial source and
-- destination instead of forcing Flutter to infer them from generic records.
create or replace function public.erp_r27_inventory_movement_log(
  p_company_id uuid,p_product_id text default null
) returns setof jsonb
language sql stable security definer set search_path=public
as $$
with base as (
  select m.*, lower(coalesce(m.data->>'referenceType',m.data->>'reference_type','')) ref_type,
         coalesce(m.data->>'referenceId',m.data->>'reference_id') ref_id,
         coalesce(m.data->>'warehouseId',m.data->>'warehouse_id') warehouse_id,
         coalesce(m.data->>'productId',m.data->>'product_id') product_id
  from public.erp_inventory_movements m
  where m.company_id=p_company_id and not m.is_deleted
    and (p_product_id is null or coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id)
    and public.erp_is_company_member(p_company_id)
), enriched as (
select b.*,
       d.parent_id,d.document_number,d.created_by document_user_id,
       coalesce(d.effective_at,d.created_at,b.created_at) operational_at,
       po.supplier_id,so.customer_id,
       coalesce(s.data->>'name',concat_ws(' ',s.data->>'firstName',s.data->>'lastName')) supplier_name,
       coalesce(c.data->>'name',concat_ws(' ',c.data->>'firstName',c.data->>'lastName')) customer_name,
       coalesce(w.data->>'name',w.data->>'code',b.warehouse_id) warehouse_name,
       coalesce(i.data->>'name',i.data->>'code',b.product_id) product_name,
       coalesce(i.data->>'code','') product_code,
       coalesce(pr.full_name,b.created_by::text,d.created_by::text) performed_by
from base b
left join public.erp_commercial_workflow_documents d
  on d.company_id=b.company_id and d.id::text=b.ref_id
left join public.erp_purchase_orders_cloud po
  on b.ref_type like 'purchase%' and po.company_id=b.company_id and po.id=d.parent_id
left join public.erp_sales_orders_cloud so
  on b.ref_type like 'sales%' and so.company_id=b.company_id and so.id=d.parent_id
left join public.erp_suppliers s on s.company_id=b.company_id and s.id=po.supplier_id and not s.is_deleted
left join public.erp_customers c on c.company_id=b.company_id and c.id=so.customer_id and not c.is_deleted
left join public.erp_warehouses w on w.company_id=b.company_id and w.id=b.warehouse_id and not w.is_deleted
left join public.erp_inventory i on i.company_id=b.company_id and i.id=b.product_id and not i.is_deleted
left join public.profiles pr on pr.id=coalesce(d.created_by,b.created_by)
)
select e.data || jsonb_build_object(
  'id',e.id,'productId',e.product_id,'productName',e.product_name,'productCode',e.product_code,
  'warehouseId',e.warehouse_id,'warehouseName',e.warehouse_name,
  'movementDate',coalesce(e.data->>'movementDate',e.operational_at::text),
  'operationalAt',e.operational_at,'performedBy',e.performed_by,
  'referenceDocumentNumber',coalesce(e.document_number,e.data->>'notes',e.ref_id),
  'sourceName',case when e.ref_type like 'purchase%' then coalesce(e.supplier_name,'Supplier')
                    when e.ref_type like 'sales%' then e.warehouse_name
                    else coalesce(e.data->>'fromWarehouseName',e.data->>'fromWarehouseId',e.warehouse_name) end,
  'destinationName',case when e.ref_type like 'purchase%' then e.warehouse_name
                         when e.ref_type like 'sales%' then coalesce(e.customer_name,'Customer')
                         else coalesce(e.data->>'toWarehouseName',e.data->>'toWarehouseId',e.warehouse_name) end,
  '_cloudUpdatedAt',e.updated_at
)
from enriched e
order by e.operational_at desc,e.created_at desc,e.id desc
$$;
revoke all on function public.erp_r27_inventory_movement_log(uuid,text) from public,anon;
grant execute on function public.erp_r27_inventory_movement_log(uuid,text) to authenticated,service_role;

-- Make the old R22 command an explicit wrapper too, so old cached clients and
-- the new R27 client both have a valid exposed endpoint.
do $$
declare r regprocedure;
begin
  for r in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='erp_r22_phase26_cloud_command'
  loop execute format('drop function %s', r); end loop;
end $$;
create function public.erp_r22_phase26_cloud_command(p_area text,p_action text,p_payload jsonb)
returns jsonb language sql security definer set search_path=public
as $$ select public.erp_r14_phase26_cloud_command($1,$2,coalesce($3,'{}'::jsonb)) $$;
revoke all on function public.erp_r22_phase26_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r22_phase26_cloud_command(text,text,jsonb) to authenticated,service_role;

grant usage on schema public to authenticated,service_role;
notify pgrst,'reload schema';
commit;
