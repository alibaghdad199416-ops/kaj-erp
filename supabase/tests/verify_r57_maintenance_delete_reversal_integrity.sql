-- R57 maintenance delete/reversal integrity runtime invariant checks.
-- Run against the LOCAL Supabase database after migration 20260813004000.
do $$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from public.erp_maintenance_material_issues as i
  join public.erp_maintenance_orders as o
    on o.company_id=i.company_id and o.id=i.maintenance_order_id
  where o.is_deleted and i.status='executed';
  if v_count<>0 then
    raise exception 'r57_deleted_maintenance_has_executed_issue_events:%',v_count;
  end if;

  select count(*) into v_count
  from public.erp_inventory_fifo_consumptions as fc
  join public.erp_maintenance_material_issues as i
    on i.company_id=fc.company_id and i.id=fc.delivery_id
  join public.erp_maintenance_orders as o
    on o.company_id=i.company_id and o.id=i.maintenance_order_id
  where o.is_deleted and fc.status='active';
  if v_count<>0 then
    raise exception 'r57_deleted_maintenance_has_active_fifo:%',v_count;
  end if;

  select count(*) into v_count
  from (
    select i.company_id,i.id,
      coalesce(sum(public.erp_try_numeric(m.data->>'quantity',0)),0) as movement_balance
    from public.erp_maintenance_material_issues as i
    join public.erp_maintenance_orders as o
      on o.company_id=i.company_id and o.id=i.maintenance_order_id
    left join public.erp_inventory_movements as m
      on m.company_id=i.company_id
     and not m.is_deleted
     and coalesce(m.data->>'referenceId',m.data->>'reference_id')=i.id::text
     and lower(coalesce(m.data->>'movementType',m.data->>'movement_type',''))
         in ('maintenance_out','maintenance_return')
    where o.is_deleted
    group by i.company_id,i.id
    having abs(coalesce(sum(public.erp_try_numeric(m.data->>'quantity',0)),0))>0.0001
  ) as q;
  if v_count<>0 then
    raise exception 'r57_deleted_maintenance_inventory_movement_not_balanced:%',v_count;
  end if;

  select count(*) into v_count
  from public.erp_journal_entries as je
  join public.erp_maintenance_orders as o
    on o.company_id=je.company_id
   and o.is_deleted
   and (
     coalesce(
       je.data->>'maintenanceOrderId',je.data->>'maintenance_order_id',
       je.data->>'orderId',je.data->>'order_id'
     )=o.id::text
     or (
       coalesce(je.data->>'referenceId',je.data->>'reference_id')=o.id::text
       and lower(coalesce(
         je.data->>'referenceType',je.data->>'reference_type',''
       )) like 'maintenance%'
     )
   )
  where not je.is_deleted
    and lower(coalesce(
      je.data->>'referenceType',je.data->>'reference_type',''
    ))<>'partner_advance';
  if v_count<>0 then
    raise exception 'r57_deleted_maintenance_has_active_nonpayment_journal:%',v_count;
  end if;

  select count(*) into v_count
  from public.erp_maintenance_payments as mp
  join public.erp_maintenance_orders as o
    on o.company_id=mp.company_id and o.id=mp.maintenance_order_id
  left join public.erp_cash_transactions as ct
    on ct.company_id=mp.company_id
   and ct.id=coalesce(mp.cash_transaction_id,mp.source_cash_transaction_id)
  where o.is_deleted
    and not mp.is_deleted
    and not coalesce(mp.is_advance_application,false)
    and (
      not coalesce(mp.is_unapplied,false)
      or ct.id is null
      or ct.is_deleted
      or lower(coalesce(
        ct.data->>'referenceType',ct.data->>'reference_type',''
      ))<>'partner_advance'
    );
  if v_count<>0 then
    raise exception 'r57_deleted_maintenance_payment_not_preserved_as_partner_advance:%',v_count;
  end if;
end $$;

select 'R57 maintenance delete/reversal integrity PASS' as result;
