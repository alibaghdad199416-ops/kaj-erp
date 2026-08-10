begin;

-- Sold-vehicle selector: keep identifiers as text so legacy non-UUID ids remain
-- selectable, and expose the full vehicle card in a stable display label.
drop function if exists public.erp_list_cloud_maintenance_eligible_cars(uuid);
create function public.erp_list_cloud_maintenance_eligible_cars(p_company_id uuid)
returns table(
  "carId" text,
  "displayName" text,
  "customerId" text,
  "customerName" text,
  "saleSequence" integer
)
language sql security definer set search_path=public as $$
  with latest_sale as (
    select distinct on (coalesce(nullif(s.data->>'carId',''),nullif(s.data->>'vehicleId','')))
      coalesce(nullif(s.data->>'carId',''),nullif(s.data->>'vehicleId','')) car_id,
      coalesce(nullif(s.data->>'customerId',''),nullif(s.data->>'clientId','')) customer_id,
      public.erp_try_numeric(s.data->>'saleSequence',0)::integer sale_sequence
    from public.erp_sales s
    where s.company_id=p_company_id and not s.is_deleted
      and coalesce(nullif(s.data->>'carId',''),nullif(s.data->>'vehicleId','')) is not null
      and coalesce(nullif(s.data->>'customerId',''),nullif(s.data->>'clientId','')) is not null
      and lower(coalesce(s.data->>'status','completed')) not in ('cancelled','deleted')
    order by coalesce(nullif(s.data->>'carId',''),nullif(s.data->>'vehicleId','')),
      public.erp_try_numeric(s.data->>'saleSequence',0) desc,
      coalesce(s.data->>'saleDate',s.created_at::text) desc
  )
  select c.id::text,
    concat_ws(' • ',
      nullif(concat_ws(' ',c.data->>'brand',c.data->>'model',c.data->>'year'),' '),
      case when nullif(c.data->>'chassis','') is not null then 'VIN: '||(c.data->>'chassis') end,
      case when nullif(c.data->>'plateNumber','') is not null then 'Plate: '||(c.data->>'plateNumber') end,
      case when nullif(c.data->>'carNumber','') is not null then 'No: '||(c.data->>'carNumber') end,
      case when nullif(c.data->>'color','') is not null then 'Color: '||(c.data->>'color') end
    ),
    ls.customer_id,
    coalesce(nullif(cu.data->>'name',''),nullif(concat_ws(' ',cu.data->>'firstName',cu.data->>'lastName'),' '),ls.customer_id),
    ls.sale_sequence
  from latest_sale ls
  join public.erp_cars c on c.company_id=p_company_id and c.id::text=ls.car_id and not c.is_deleted
  left join public.erp_customers cu on cu.company_id=p_company_id and cu.id::text=ls.customer_id and not cu.is_deleted
  where public.erp_active_company_context(p_company_id) is not null
  order by 2;
$$;
revoke all on function public.erp_list_cloud_maintenance_eligible_cars(uuid) from public,anon;
grant execute on function public.erp_list_cloud_maintenance_eligible_cars(uuid) to authenticated;

-- Legacy-safe maintenance deletion. Every reversible accounting/inventory link is
-- voided first; malformed old references are then soft-deleted directly.
create or replace function public.erp_delete_cloud_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype;
  v_reason text := coalesce(nullif(btrim(p_reason),''),'حذف أمر الصيانة وتحديث ارتباطاته');
begin
  perform public.erp_active_company_context(p_company_id);
  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id for update;
  if not found then raise exception 'أمر الصيانة غير موجود'; end if;
  if o.is_deleted then return; end if;

  begin
    perform public.erp_cancel_cloud_maintenance_order(p_company_id,p_order_id,v_reason);
  exception when others then null;
  end;

  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_invoice',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_payment',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance',p_order_id::text); exception when others then null; end;

  update public.erp_inventory_movements
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and not is_deleted
     and coalesce(data->>'referenceId',data->>'reference_id',data->>'maintenanceOrderId')=p_order_id::text;

  update public.erp_cash_transactions
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and not is_deleted
     and coalesce(data->>'referenceId',data->>'reference_id',data->>'maintenanceOrderId')=p_order_id::text;

  update public.erp_maintenance_parts
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
  update public.erp_maintenance_payments
     set is_deleted=true,deleted_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
  update public.erp_maintenance_orders
     set paid_amount=0,status='cancelled',workflow_stage='cancelled',cancel_reason=v_reason,
         is_deleted=true,deleted_at=now(),deleted_by=auth.uid(),deleted_reason=v_reason,updated_at=now()
   where company_id=p_company_id and id=p_order_id;
end $$;
revoke all on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) from public,anon;
grant execute on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) to authenticated;

commit;
