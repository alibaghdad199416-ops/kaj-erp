begin;

-- R57 Maintenance delete/reversal integrity closure.
--
-- The R57 material-issue lifecycle owns stock/FIFO by issue event UUID, while
-- the historical delete path still reversed legacy order-owned movements.
-- Deleting a maintenance order therefore could soft-delete the order while
-- leaving R57 issue events, stock consumption, FIFO consumption, and exact
-- invoice-owned accounting active. Payments are intentionally preserved as
-- customer unapplied balances and remain cashbox/accounting-owned.

create or replace function public.erp_r57_reverse_maintenance_issue_for_delete(
  p_company_id uuid,
  p_order_id uuid,
  p_issue_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_issue public.erp_maintenance_material_issues%rowtype;
  v_line record;
  v_fifo record;
  v_stock public.erp_warehouse_stock%rowtype;
  v_fifo_quantity numeric;
  v_issued_quantity numeric;
  v_returned_quantity numeric;
  v_restore_quantity numeric;
  v_restored_total numeric:=0;
  v_reason text:=coalesce(
    nullif(btrim(coalesce(p_reason,'')),''),
    'Maintenance order deletion'
  );
begin
  select i.* into v_issue
  from public.erp_maintenance_material_issues as i
  where i.company_id=p_company_id
    and i.id=p_issue_id
    and i.maintenance_order_id=p_order_id
  for update;

  if not found then
    raise exception 'maintenance_delete_issue_not_found:%',p_issue_id;
  end if;
  if v_issue.status='reversed' then
    return jsonb_build_object(
      'issueId',p_issue_id,
      'alreadyReversed',true,
      'restoredQuantity',0
    );
  end if;

  -- Validate every product/warehouse pair before mutating anything. The active
  -- FIFO quantity must match the outstanding material-out quantity for the
  -- event. This fails closed instead of guessing when historical ledgers are
  -- inconsistent.
  for v_line in
    select
      il.product_id,
      il.warehouse_id,
      sum(il.quantity) as quantity,
      sum(il.actual_cost) as actual_cost
    from public.erp_maintenance_material_issue_lines as il
    where il.company_id=p_company_id
      and il.issue_id=p_issue_id
      and il.maintenance_order_id=p_order_id
    group by il.product_id,il.warehouse_id
  loop
    select coalesce(sum(fc.quantity),0)
    into v_fifo_quantity
    from public.erp_inventory_fifo_consumptions as fc
    where fc.company_id=p_company_id
      and fc.delivery_id=p_issue_id
      and fc.sales_order_id=p_order_id
      and fc.item_type='product'
      and fc.item_id=v_line.product_id
      and fc.warehouse_id=v_line.warehouse_id
      and fc.status='active';

    select coalesce(sum(abs(public.erp_try_numeric(m.data->>'quantity',0))),0)
    into v_issued_quantity
    from public.erp_inventory_movements as m
    where m.company_id=p_company_id
      and not m.is_deleted
      and coalesce(m.data->>'referenceId',m.data->>'reference_id')=p_issue_id::text
      and lower(coalesce(m.data->>'referenceType',m.data->>'reference_type',''))='maintenance_issue'
      and lower(coalesce(m.data->>'movementType',m.data->>'movement_type',''))='maintenance_out'
      and coalesce(m.data->>'productId',m.data->>'product_id')=v_line.product_id
      and coalesce(m.data->>'warehouseId',m.data->>'warehouse_id')=v_line.warehouse_id;

    select coalesce(sum(abs(public.erp_try_numeric(m.data->>'quantity',0))),0)
    into v_returned_quantity
    from public.erp_inventory_movements as m
    where m.company_id=p_company_id
      and not m.is_deleted
      and coalesce(m.data->>'referenceId',m.data->>'reference_id')=p_issue_id::text
      and lower(coalesce(m.data->>'movementType',m.data->>'movement_type',''))='maintenance_return'
      and coalesce(m.data->>'productId',m.data->>'product_id')=v_line.product_id
      and coalesce(m.data->>'warehouseId',m.data->>'warehouse_id')=v_line.warehouse_id;

    v_restore_quantity:=greatest(v_issued_quantity-v_returned_quantity,0);

    -- Historical deletion may already have repaired one side of the ledger
    -- (FIFO or quantity) while leaving the other side active. Reconcile each
    -- side independently, but fail closed if either active side exceeds the
    -- authoritative issue-line quantity.
    if v_fifo_quantity>coalesce(v_line.quantity,0)+0.0001
       or v_restore_quantity>coalesce(v_line.quantity,0)+0.0001 then
      raise exception
        'maintenance_delete_issue_reversal_exceeds_event:issue=%:product=%:warehouse=%:event=%:fifo=%:stock=%',
        p_issue_id,v_line.product_id,v_line.warehouse_id,
        v_line.quantity,v_fifo_quantity,v_restore_quantity;
    end if;
  end loop;

  -- Return the value to the exact FIFO layers consumed by this issue event.
  for v_fifo in
    select fc.layer_id,fc.quantity
    from public.erp_inventory_fifo_consumptions as fc
    where fc.company_id=p_company_id
      and fc.delivery_id=p_issue_id
      and fc.sales_order_id=p_order_id
      and fc.status='active'
    order by fc.effective_at,fc.created_at,fc.id
    for update
  loop
    update public.erp_inventory_cost_layers as l
    set remaining_quantity=least(
          l.original_quantity,
          l.remaining_quantity+v_fifo.quantity
        ),
        status='active',
        updated_at=now(),
        updated_by=auth.uid()
    where l.company_id=p_company_id
      and l.id=v_fifo.layer_id;
  end loop;

  update public.erp_inventory_fifo_consumptions as fc
  set status='reversed',
      reversed_at=coalesce(fc.reversed_at,now())
  where fc.company_id=p_company_id
    and fc.delivery_id=p_issue_id
    and fc.sales_order_id=p_order_id
    and fc.status='active';

  -- Restore quantity only for the outstanding event-owned movement. This keeps
  -- the operation idempotent even when a historical row was partly repaired.
  for v_line in
    select
      il.product_id,
      il.warehouse_id,
      sum(il.quantity) as quantity,
      sum(il.actual_cost) as actual_cost
    from public.erp_maintenance_material_issue_lines as il
    where il.company_id=p_company_id
      and il.issue_id=p_issue_id
      and il.maintenance_order_id=p_order_id
    group by il.product_id,il.warehouse_id
  loop
    select coalesce(sum(abs(public.erp_try_numeric(m.data->>'quantity',0))),0)
    into v_issued_quantity
    from public.erp_inventory_movements as m
    where m.company_id=p_company_id
      and not m.is_deleted
      and coalesce(m.data->>'referenceId',m.data->>'reference_id')=p_issue_id::text
      and lower(coalesce(m.data->>'referenceType',m.data->>'reference_type',''))='maintenance_issue'
      and lower(coalesce(m.data->>'movementType',m.data->>'movement_type',''))='maintenance_out'
      and coalesce(m.data->>'productId',m.data->>'product_id')=v_line.product_id
      and coalesce(m.data->>'warehouseId',m.data->>'warehouse_id')=v_line.warehouse_id;

    select coalesce(sum(abs(public.erp_try_numeric(m.data->>'quantity',0))),0)
    into v_returned_quantity
    from public.erp_inventory_movements as m
    where m.company_id=p_company_id
      and not m.is_deleted
      and coalesce(m.data->>'referenceId',m.data->>'reference_id')=p_issue_id::text
      and lower(coalesce(m.data->>'movementType',m.data->>'movement_type',''))='maintenance_return'
      and coalesce(m.data->>'productId',m.data->>'product_id')=v_line.product_id
      and coalesce(m.data->>'warehouseId',m.data->>'warehouse_id')=v_line.warehouse_id;

    v_restore_quantity:=greatest(v_issued_quantity-v_returned_quantity,0);
    if v_restore_quantity<=0 then
      continue;
    end if;

    v_stock:=public.erp_inventory_ensure_stock(
      p_company_id,v_line.warehouse_id,v_line.product_id
    );
    update public.erp_warehouse_stock as ws
    set data=ws.data||jsonb_build_object(
          'quantity',public.erp_try_numeric(ws.data->>'quantity',0)+v_restore_quantity,
          'updatedAt',now()
        ),
        updated_at=now(),
        updated_by=auth.uid()
    where ws.company_id=p_company_id
      and ws.id=v_stock.id;

    perform public.erp_inventory_insert_movement(
      p_company_id,
      v_line.product_id,
      v_line.warehouse_id,
      'maintenance_return',
      v_restore_quantity,
      case
        when coalesce(v_line.quantity,0)>0
          then coalesce(v_line.actual_cost,0)/v_line.quantity
        else 0
      end,
      'maintenance_issue_reversal',
      p_issue_id::text,
      v_reason
    );
    perform public.erp_inventory_refresh_product(
      p_company_id,v_line.product_id
    );
    v_restored_total:=v_restored_total+v_restore_quantity;
  end loop;

  update public.erp_maintenance_material_issues as i
  set status='reversed',
      reversed_at=coalesce(i.reversed_at,now()),
      reversed_by=coalesce(i.reversed_by,auth.uid()),
      reversal_reason=coalesce(i.reversal_reason,v_reason)
  where i.company_id=p_company_id
    and i.id=p_issue_id;

  return jsonb_build_object(
    'issueId',p_issue_id,
    'alreadyReversed',false,
    'restoredQuantity',v_restored_total
  );
end;
$$;

create or replace function public.erp_r57_reverse_maintenance_issues_for_delete(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_issue record;
  v_result jsonb;
  v_count integer:=0;
  v_quantity numeric:=0;
begin
  for v_issue in
    select i.id
    from public.erp_maintenance_material_issues as i
    where i.company_id=p_company_id
      and i.maintenance_order_id=p_order_id
      and i.status='executed'
    order by i.created_at desc,i.id desc
  loop
    v_result:=public.erp_r57_reverse_maintenance_issue_for_delete(
      p_company_id,p_order_id,v_issue.id,p_reason
    );
    v_count:=v_count+1;
    v_quantity:=v_quantity+public.erp_try_numeric(
      v_result->>'restoredQuantity',0
    );
  end loop;

  return jsonb_build_object(
    'reversedIssueCount',v_count,
    'restoredQuantity',v_quantity
  );
end;
$$;

create or replace function public.erp_r57_reverse_maintenance_accounting_for_delete(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_cost_entry jsonb;
  v_journal record;
  v_entry_id text;
  v_voided integer:=0;
  v_car public.erp_cars%rowtype;
  v_car_maintenance numeric;
  v_car_patch jsonb;
  v_reason text:=coalesce(
    nullif(btrim(coalesce(p_reason,'')),''),
    'Maintenance order deletion'
  );
begin
  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id
    and o.id=p_order_id
  for update;
  if not found then
    raise exception 'maintenance_order_not_found';
  end if;

  -- Void the exact invoice-owned revenue and cost journals first.
  if nullif(btrim(coalesce(v_order.invoice_journal_entry_id,'')),'') is not null then
    if exists(
      select 1 from public.erp_journal_entries as je
      where je.company_id=p_company_id
        and je.id=v_order.invoice_journal_entry_id
        and not je.is_deleted
    ) then
      v_voided:=v_voided+1;
    end if;
    perform public.erp_v736_void_journal_id(
      p_company_id,v_order.invoice_journal_entry_id
    );
  end if;

  for v_cost_entry in
    select value
    from jsonb_array_elements(
      coalesce(v_order.cost_journal_entry_ids,'[]'::jsonb)
    )
  loop
    v_entry_id:=case
      when jsonb_typeof(v_cost_entry)='string'
        then trim(both '"' from v_cost_entry::text)
      else coalesce(
        v_cost_entry->>'journalEntryId',
        v_cost_entry->>'journal_entry_id'
      )
    end;
    if nullif(btrim(coalesce(v_entry_id,'')),'') is null then
      continue;
    end if;
    if exists(
      select 1 from public.erp_journal_entries as je
      where je.company_id=p_company_id
        and je.id=v_entry_id
        and not je.is_deleted
    ) then
      v_voided:=v_voided+1;
    end if;
    perform public.erp_v736_void_journal_id(p_company_id,v_entry_id);
  end loop;

  -- Catch any legacy/current maintenance journal that is still tied to this
  -- order but was not present in the cached order fields. Payment journals have
  -- already been detached to partner_advance before this helper is called and
  -- are explicitly excluded.
  for v_journal in
    select je.id
    from public.erp_journal_entries as je
    where je.company_id=p_company_id
      and not je.is_deleted
      and lower(coalesce(
        je.data->>'referenceType',je.data->>'reference_type',''
      ))<>'partner_advance'
      and (
        coalesce(
          je.data->>'maintenanceOrderId',
          je.data->>'maintenance_order_id',
          je.data->>'orderId',
          je.data->>'order_id'
        )=p_order_id::text
        or (
          coalesce(
            je.data->>'referenceId',je.data->>'reference_id'
          )=p_order_id::text
          and lower(coalesce(
            je.data->>'referenceType',je.data->>'reference_type',''
          )) like 'maintenance%'
        )
      )
    order by je.created_at,je.id
  loop
    perform public.erp_v736_void_journal_id(
      p_company_id,v_journal.id
    );
    v_voided:=v_voided+1;
  end loop;

  -- An unsold vehicle can have maintenance cost capitalized by the maintenance
  -- invoice. Subtract only this order's contribution so a later valid service
  -- order is not overwritten by an old snapshot during historical repair.
  if not coalesce(v_order.is_sold_car,false)
     and coalesce(v_order.car_cost_added,0)>0 then
    select c.* into v_car
    from public.erp_cars as c
    where c.company_id=p_company_id
      and c.id=coalesce(v_order.source_car_id,v_order.car_id::text)
      and not c.is_deleted
    for update;
    if found then
      v_car_maintenance:=greatest(
        0,
        public.erp_try_numeric(
          coalesce(v_car.data->>'maintenanceCost',v_car.data->>'maintenance_cost'),
          0
        )-v_order.car_cost_added
      );
      v_car_patch:=jsonb_build_object(
        'maintenanceCost',v_car_maintenance,
        'maintenance_cost',v_car_maintenance,
        'updatedAt',now()
      );
      if coalesce(v_car.data->>'maintenanceValuationInvoiceId','')=p_order_id::text then
        v_car_patch:=v_car_patch||jsonb_build_object(
          'maintenanceValuationInvoiceId',null,
          'maintenanceCostByCurrency','{}'::jsonb
        );
      end if;
      update public.erp_cars as c
      set data=c.data||v_car_patch,
          updated_at=now(),
          updated_by=auth.uid()
      where c.company_id=p_company_id
        and c.id=v_car.id;
    end if;
  end if;

  update public.erp_maintenance_orders as o
  set car_cost_added=0,
      invoice_journal_entry_id=null,
      cost_journal_entry_ids='[]'::jsonb,
      accounting_payload=coalesce(o.accounting_payload,'{}'::jsonb)||jsonb_build_object(
        'deleteAccountingReversedAt',now(),
        'deleteAccountingReason',v_reason,
        'deletedInvoiceJournalEntryId',v_order.invoice_journal_entry_id,
        'deletedCostJournalEntryIds',coalesce(v_order.cost_journal_entry_ids,'[]'::jsonb),
        'deletedCarCostAdded',coalesce(v_order.car_cost_added,0)
      ),
      updated_at=now()
  where o.company_id=p_company_id
    and o.id=p_order_id;

  return jsonb_build_object(
    'voidedJournalCount',v_voided,
    'invoiceAccountingReversed',true
  );
end;
$$;

-- Canonical delete path after R57 material issues:
-- 1) preserve/detach cash payment;
-- 2) void exact invoice-owned accounting;
-- 3) reverse every executed event-owned stock/FIFO issue;
-- 4) run the established soft-delete/recycle-bin closure.
create or replace function public.erp_delete_cloud_maintenance_order_v3(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_reason text:=coalesce(
    nullif(btrim(coalesce(p_reason,'')),''),
    'Maintenance order deleted'
  );
  v_detached jsonb;
  v_accounting jsonb;
  v_issues jsonb;
  v_result jsonb;
  v_normalized integer;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.delete']
  );

  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id
    and o.id=p_order_id
  for update;
  if not found then
    raise exception 'maintenance_order_not_found';
  end if;
  if v_order.is_deleted then
    return jsonb_build_object(
      'deleted',true,
      'alreadyDeleted',true,
      'module','maintenance',
      'orderId',p_order_id,
      'paymentsPreserved',true,
      'paymentPolicy','partner_balance_preserved'
    );
  end if;

  v_detached:=public.erp_v731_detach_maintenance_payments(
    p_company_id,p_order_id,v_reason
  );
  v_accounting:=public.erp_r57_reverse_maintenance_accounting_for_delete(
    p_company_id,p_order_id,v_reason
  );
  v_issues:=public.erp_r57_reverse_maintenance_issues_for_delete(
    p_company_id,p_order_id,v_reason
  );

  v_result:=public.erp_delete_cloud_maintenance_order_v2(
    p_company_id,p_order_id,v_reason
  );
  v_normalized:=public.erp_v731_normalize_order_advances(
    p_company_id,p_order_id
  );

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','partner_balance_preserved',
    'paymentsRequiredDeleted',false,
    'paymentsPreserved',true,
    'detachment',v_detached,
    'accountingReversal',v_accounting,
    'materialIssueReversal',v_issues,
    'normalizedAdvances',v_normalized,
    'futureAllocation','same_customer_same_currency'
  );
end;
$$;

-- Repair helpers for orders that were already deleted before this migration.
-- Each order is repaired in its own PL/pgSQL exception block. A failed historical
-- row is rolled back atomically and returns the exact failing stage/SQLSTATE
-- instead of aborting the migration and hiding the useful database error.
create or replace function public.erp_r57_repair_deleted_maintenance_order(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_stage text:='load_order';
  v_detached jsonb;
  v_accounting jsonb;
  v_issues jsonb;
  v_normalized integer;
  v_detail text;
  v_hint text;
  v_context text;
begin
  begin
    select o.* into v_order
    from public.erp_maintenance_orders as o
    where o.company_id=p_company_id
      and o.id=p_order_id
    for update;

    if not found then
      return jsonb_build_object(
        'ok',false,'companyId',p_company_id,'orderId',p_order_id,
        'stage',v_stage,'sqlstate','P0002','error','maintenance_order_not_found'
      );
    end if;

    if not v_order.is_deleted then
      return jsonb_build_object(
        'ok',false,'companyId',p_company_id,'orderId',p_order_id,
        'stage',v_stage,'sqlstate','22023','error','maintenance_order_not_deleted'
      );
    end if;

    v_stage:='detach_payments';
    v_detached:=public.erp_v731_detach_maintenance_payments(
      p_company_id,p_order_id,
      'R57 repair of previously deleted maintenance order'
    );

    v_stage:='reverse_invoice_accounting';
    v_accounting:=public.erp_r57_reverse_maintenance_accounting_for_delete(
      p_company_id,p_order_id,
      'R57 repair of previously deleted maintenance order'
    );

    v_stage:='reverse_material_issues';
    v_issues:=public.erp_r57_reverse_maintenance_issues_for_delete(
      p_company_id,p_order_id,
      'R57 repair of previously deleted maintenance order'
    );

    v_stage:='normalize_preserved_payments';
    v_normalized:=public.erp_v731_normalize_order_advances(
      p_company_id,p_order_id
    );

    return jsonb_build_object(
      'ok',true,
      'companyId',p_company_id,
      'orderId',p_order_id,
      'stage','complete',
      'detachment',v_detached,
      'accountingReversal',v_accounting,
      'materialIssueReversal',v_issues,
      'normalizedAdvances',v_normalized,
      'paymentsPreserved',true
    );
  exception when others then
    get stacked diagnostics
      v_detail=pg_exception_detail,
      v_hint=pg_exception_hint,
      v_context=pg_exception_context;
    return jsonb_build_object(
      'ok',false,
      'companyId',p_company_id,
      'orderId',p_order_id,
      'stage',v_stage,
      'sqlstate',sqlstate,
      'error',sqlerrm,
      'detail',coalesce(v_detail,''),
      'hint',coalesce(v_hint,''),
      'context',coalesce(v_context,'')
    );
  end;
end;
$$;

create or replace function public.erp_r57_repair_deleted_maintenance_orders(
  p_company_id uuid default null
) returns setof jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order record;
begin
  for v_order in
    select o.company_id,o.id
    from public.erp_maintenance_orders as o
    where o.is_deleted
      and (p_company_id is null or o.company_id=p_company_id)
      and (
        exists(
          select 1
          from public.erp_maintenance_material_issues as i
          where i.company_id=o.company_id
            and i.maintenance_order_id=o.id
            and i.status='executed'
        )
        or nullif(btrim(coalesce(o.invoice_journal_entry_id,'')),'') is not null
        or (
          jsonb_typeof(coalesce(o.cost_journal_entry_ids,'[]'::jsonb))='array'
          and jsonb_array_length(coalesce(o.cost_journal_entry_ids,'[]'::jsonb))>0
        )
        or exists(
          select 1
          from public.erp_journal_entries as je
          where je.company_id=o.company_id
            and not je.is_deleted
            and lower(coalesce(
              je.data->>'referenceType',je.data->>'reference_type',''
            ))<>'partner_advance'
            and (
              coalesce(
                je.data->>'maintenanceOrderId',
                je.data->>'maintenance_order_id',
                je.data->>'orderId',
                je.data->>'order_id'
              )=o.id::text
              or (
                coalesce(
                  je.data->>'referenceId',je.data->>'reference_id'
                )=o.id::text
                and lower(coalesce(
                  je.data->>'referenceType',je.data->>'reference_type',''
                )) like 'maintenance%'
              )
            )
        )
      )
    order by o.deleted_at,o.id
  loop
    return next public.erp_r57_repair_deleted_maintenance_order(
      v_order.company_id,v_order.id
    );
  end loop;
  return;
end;
$$;

-- Best-effort one-time repair. Any inconsistent historical row is left untouched
-- by its inner exception subtransaction and reported as a warning. The migration
-- itself still installs the corrected future delete path and the diagnostic
-- repair RPC, so the exact row can be inspected and repaired deterministically.
do $$
declare
  v_result jsonb;
begin
  for v_result in
    select * from public.erp_r57_repair_deleted_maintenance_orders(null)
  loop
    if not coalesce((v_result->>'ok')::boolean,false) then
      raise warning 'R57 deleted maintenance repair pending: %',v_result;
    end if;
  end loop;
end $$;

revoke all on function public.erp_r57_reverse_maintenance_issue_for_delete(uuid,uuid,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.erp_r57_reverse_maintenance_issues_for_delete(uuid,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.erp_r57_reverse_maintenance_accounting_for_delete(uuid,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.erp_delete_cloud_maintenance_order_v3(uuid,uuid,text)
  from public,anon;
revoke all on function public.erp_r57_repair_deleted_maintenance_order(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.erp_r57_repair_deleted_maintenance_orders(uuid)
  from public,anon,authenticated;
grant execute on function public.erp_delete_cloud_maintenance_order_v3(uuid,uuid,text)
  to authenticated,service_role;
grant execute on function public.erp_r57_repair_deleted_maintenance_order(uuid,uuid)
  to service_role;
grant execute on function public.erp_r57_repair_deleted_maintenance_orders(uuid)
  to service_role;

notify pgrst,'reload schema';
commit;
