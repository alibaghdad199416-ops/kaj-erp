begin;

-- Quality Line ERP / KAJ ERP — R92 comprehensive module audit.
-- Forward-only closure for journal balance readback and legacy mutation bypasses.

-- ---------------------------------------------------------------------------
-- 1. Journal entry list with permission-safe server-computed balance metadata.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r92_list_journal_entries(
  p_company_id uuid
) returns setof jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_row jsonb;
  v_debit numeric;
  v_credit numeric;
  v_diff numeric;
  v_can_balance boolean;
begin
  perform public.erp_active_company_context(p_company_id);

  v_can_balance := public.is_company_admin(p_company_id)
    or (
      public.erp_cloud_user_can_view_field(p_company_id,'accounting','debit',null)
      and public.erp_cloud_user_can_view_field(p_company_id,'accounting','credit',null)
      and public.erp_cloud_user_can_view_field(p_company_id,'accounting','balances',null)
    );

  for v_row in
    select value
    from public.erp_r9_list_cloud_master_records(
      p_company_id,'erp_journal_entries'
    ) as value
  loop
    -- Never reconstruct hidden debit/credit values from raw storage. The
    -- generic R9 reader has already applied record scope + field visibility.
    if v_can_balance and v_row ? 'totalDebit' and v_row ? 'totalCredit' then
      v_debit := public.erp_try_numeric(v_row->>'totalDebit',0);
      v_credit := public.erp_try_numeric(v_row->>'totalCredit',0);
      v_diff := v_debit-v_credit;
      v_row := v_row || jsonb_build_object(
        'balanceDifference',v_diff,
        'isBalanced',(v_debit>0 and abs(v_diff)<=0.01)
      );
    end if;
    return next v_row;
  end loop;
  return;
end;
$$;

revoke all on function public.erp_r92_list_journal_entries(uuid)
  from public,anon;
grant execute on function public.erp_r92_list_journal_entries(uuid)
  to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 2. Legacy direct stock receive/sell endpoints are not valid operational
--    entry points. Inventory is owned by approved workflow documents.
-- ---------------------------------------------------------------------------
revoke all on function public.erp_r49_receive_inventory_stock(
  uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text
) from public,anon,authenticated;
grant execute on function public.erp_r49_receive_inventory_stock(
  uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text
) to service_role;

revoke all on function public.erp_receive_inventory_stock(
  uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text
) from public,anon,authenticated;
grant execute on function public.erp_receive_inventory_stock(
  uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text
) to service_role;

revoke all on function public.erp_sell_inventory_stock(
  uuid,text,text,integer,numeric,text,text
) from public,anon,authenticated;
grant execute on function public.erp_sell_inventory_stock(
  uuid,text,text,integer,numeric,text,text
) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Legacy sale/purchase register delete RPCs used a broad historical role
--    check. R92 exposes exact module-delete facades and makes the old routines
--    internal-only. The R84 trigger remains the record-scope boundary.
-- ---------------------------------------------------------------------------
create or replace function public.can_manage_master_data(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.companies c on c.id=m.company_id
    where m.company_id=p_company_id
      and public.erp_membership_matches_current_user(m.user_id,m.user_uid)
      and m.is_active and c.is_active
      and (
        m.is_system_admin
        or m.role_code in ('owner','admin','manager','sales','warehouse','accountant')
        or (
          nullif(current_setting('qualityline.r49_master_permission',true),'') = any(array[
            'inventory.create','inventory.update','inventory.adjust','inventory.receive','inventory.transfer',
            'sales.create','sales.update','sales.delete',
            'purchases.create','purchases.update','purchases.delete',
            'accounting.create','accounting.update','accounting.post'
          ])
          and public.erp_cloud_user_has_permission(
            p_company_id,current_setting('qualityline.r49_master_permission',true)
          )
        )
      )
  );
$$;

create or replace function public.erp_r92_delete_cloud_sale(
  p_company_id uuid,p_sale_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.delete') then
    raise exception 'permission_denied:sales.delete' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','sales.delete',true);
  perform public.erp_delete_cloud_sale(p_company_id,p_sale_id);
  perform set_config('qualityline.r49_master_permission','',true);
end;
$$;

create or replace function public.erp_r92_delete_cloud_purchase(
  p_company_id uuid,p_purchase_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.delete') then
    raise exception 'permission_denied:purchases.delete' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','purchases.delete',true);
  perform public.erp_delete_cloud_purchase(p_company_id,p_purchase_id);
  perform set_config('qualityline.r49_master_permission','',true);
end;
$$;

revoke all on function public.erp_r92_delete_cloud_sale(uuid,text)
  from public,anon;
revoke all on function public.erp_r92_delete_cloud_purchase(uuid,text)
  from public,anon;
grant execute on function public.erp_r92_delete_cloud_sale(uuid,text)
  to authenticated,service_role;
grant execute on function public.erp_r92_delete_cloud_purchase(uuid,text)
  to authenticated,service_role;

revoke all on function public.erp_delete_cloud_sale(uuid,text)
  from public,anon,authenticated;
revoke all on function public.erp_delete_cloud_purchase(uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_delete_cloud_sale(uuid,text) to service_role;
grant execute on function public.erp_delete_cloud_purchase(uuid,text) to service_role;


-- ---------------------------------------------------------------------------
-- 4. Workflow selectors are field-aware. Cross-module dropdowns must not
--    become a side channel around warehouse/cashbox/accounting field policy.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r92_workflow_action_allowed(
  p_company_id uuid,p_module text,p_action text
) returns boolean
language plpgsql stable security definer set search_path=public as $$
declare v_legacy text;
begin
  perform public.erp_active_company_context(p_company_id);
  if p_module='sales' then
    v_legacy:=case p_action when 'delivery.create' then 'sales.update' when 'payment' then 'cashbox.receipt' else 'sales.view' end;
  elsif p_module='purchases' then
    v_legacy:=case p_action when 'receipt.create' then 'purchases.update' when 'payment' then 'cashbox.payment' else 'purchases.view' end;
  elsif p_module='maintenance' then
    v_legacy:=case p_action when 'material_issue.create' then 'maintenance.update' when 'payment' then 'cashbox.receipt' else 'maintenance.view' end;
  else
    raise exception 'invalid_workflow_module:%',p_module using errcode='22023';
  end if;
  return public.erp_r88_action_allowed(p_company_id,p_module,p_action,v_legacy);
end;
$$;

create or replace function public.erp_r92_list_workflow_cash_accounts(
  p_company_id uuid,p_module text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r92_workflow_action_allowed(p_company_id,p_module,'payment') then
    raise exception 'permission_denied:%.payment',p_module using errcode='42501';
  end if;
  -- A payment cashbox is only usable when the user is allowed to see both its
  -- identity label and currency. Returning a technical id without those fields
  -- would create an unusable and privacy-leaking selector.
  if not public.erp_cloud_user_can_view_field(p_company_id,'cashbox','name',null)
     or not public.erp_cloud_user_can_view_field(p_company_id,'cashbox','currency',null) then
    return;
  end if;
  return query
  select public.erp_r9_filter_result_json(
    p_company_id,'cashbox',
    jsonb_strip_nulls(jsonb_build_object(
      'id',c.id,
      'name',coalesce(c.data->>'name',''),
      'currency',upper(coalesce(c.data->>'currency','')),
      'linkedCashAccountId',nullif(coalesce(c.data->>'linkedCashAccountId',c.data->>'linked_cash_account_id'),'')
    )),null)
  from public.erp_cash_accounts c
  where c.company_id=p_company_id and not c.is_deleted
    and public.erp_try_boolean(coalesce(c.data->>'isActive',c.data->>'is_active'),false)
    and upper(coalesce(c.data->>'currency','')) in ('USD','IQD')
    and public.erp_r84_record_visible(p_company_id,'cashbox',c.created_by,null)
  order by coalesce(c.data->>'name',''),c.id;
end;
$$;

create or replace function public.erp_r92_list_workflow_warehouses(
  p_company_id uuid,p_module text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_action text;
begin
  perform public.erp_active_company_context(p_company_id);
  v_action:=case p_module when 'sales' then 'delivery.create' when 'purchases' then 'receipt.create' else null end;
  if v_action is null then raise exception 'invalid_workflow_module:%',p_module using errcode='22023'; end if;
  if not public.erp_r92_workflow_action_allowed(p_company_id,p_module,v_action) then
    raise exception 'permission_denied:%.%',p_module,v_action using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,p_module,'itemWarehouse',null) then
    return;
  end if;
  return query
  select public.erp_r9_filter_result_json(
    p_company_id,'warehouses',
    jsonb_build_object(
      'id',w.id,
      'name',coalesce(w.data->>'name',''),
      'code',coalesce(w.data->>'code',''),
      'address',coalesce(w.data->>'address','')
    ),null)
  from public.erp_warehouses w
  where w.company_id=p_company_id and not w.is_deleted
    and public.erp_try_boolean(coalesce(w.data->>'isActive',w.data->>'is_active'),false)
    and public.erp_r84_record_visible(p_company_id,'warehouses',w.created_by,null)
    and (
      public.erp_cloud_user_can_view_field(p_company_id,'warehouses','name',null)
      or public.erp_cloud_user_can_view_field(p_company_id,'warehouses','code',null)
    )
  order by coalesce(w.data->>'name',w.data->>'code',w.id),w.id;
end;
$$;

create or replace function public.erp_r92_list_workflow_settlement_accounts(
  p_company_id uuid,p_module text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r92_workflow_action_allowed(p_company_id,p_module,'payment') then
    raise exception 'permission_denied:%.payment',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountCode',null)
     or not public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountName',null)
     or not public.erp_cloud_user_can_view_field(p_company_id,'accounting','currency',null) then
    return;
  end if;
  return query
  select public.erp_r9_filter_result_json(
    p_company_id,'accounting',
    jsonb_build_object(
      'id',a.account_id,'code',a.code,'name',coalesce(nullif(a.name,''),a.code),
      'type',a.account_type,'currency',a.currency
    ),null)
  from public.erp_accounts a
  where a.organization_id=p_company_id and a.is_active
    and not public.erp_v763_forbidden_capitalization_account(a.code,a.name)
    and not exists(
      select 1 from public.erp_accounts child
      where child.organization_id=a.organization_id
        and child.parent_account_id=a.account_id
        and child.is_active
    )
  order by a.code,a.name;
end;
$$;

-- Filter the allocation context itself; the old R49 wrapper leaked warehouse
-- labels/address and sales stock availability even when the corresponding
-- field permissions were restricted.
create or replace function public.erp_r92_get_commercial_order_allocation_context(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_action text;
  v_context jsonb;
  v_items jsonb:='[]'::jsonb;
  v_warehouses jsonb:='[]'::jsonb;
  v_item jsonb;
  v_filtered jsonb;
  v_wh jsonb;
  v_balances jsonb;
  v_balance jsonb;
  v_filtered_balances jsonb;
  v_creator uuid;
  v_can_items boolean;
  v_can_qty boolean;
  v_can_price boolean;
  v_can_item_wh boolean;
  v_can_inventory_qty boolean;
  v_can_inventory_wh boolean;
  v_can_car_wh boolean;
begin
  perform public.erp_active_company_context(p_company_id);
  if p_module='sales' then
    v_action:='delivery.create';
    select created_by into v_creator from public.erp_sales_orders_cloud
      where company_id=p_company_id and id=p_order_id and not is_deleted;
  elsif p_module='purchases' then
    v_action:='receipt.create';
    select created_by into v_creator from public.erp_purchase_orders_cloud
      where company_id=p_company_id and id=p_order_id and not is_deleted;
  else
    raise exception 'invalid_workflow_module:%',p_module using errcode='22023';
  end if;
  if not found then raise exception 'workflow_order_not_found' using errcode='P0002'; end if;
  if not public.erp_r84_record_visible(p_company_id,p_module,v_creator,null) then
    raise exception 'record_scope_denied:%.records.own',p_module using errcode='42501';
  end if;
  if not public.erp_r92_workflow_action_allowed(p_company_id,p_module,v_action) then
    raise exception 'permission_denied:%.%',p_module,v_action using errcode='42501';
  end if;

  v_context:=public.erp_get_commercial_order_allocation_context(p_company_id,p_order_id,p_module);
  v_can_items:=public.erp_cloud_user_can_view_field(p_company_id,p_module,'items',null);
  v_can_qty:=public.erp_cloud_user_can_view_field(p_company_id,p_module,'itemQuantity',null);
  v_can_price:=public.erp_cloud_user_can_view_field(
    p_company_id,p_module,case when p_module='sales' then 'itemPrice' else 'itemCost' end,null);
  v_can_item_wh:=public.erp_cloud_user_can_view_field(p_company_id,p_module,'itemWarehouse',null);
  v_can_inventory_qty:=public.erp_cloud_user_can_view_field(p_company_id,'inventory','quantity',null);
  v_can_inventory_wh:=public.erp_cloud_user_can_view_field(p_company_id,'inventory','warehouseId',null);
  v_can_car_wh:=public.erp_cloud_user_can_view_field(p_company_id,'cars','warehouseId',null);

  if v_can_items then
    for v_item in select value from jsonb_array_elements(coalesce(v_context->'items','[]'::jsonb)) loop
      v_filtered:=jsonb_build_object(
        'itemType',v_item->'itemType','itemId',v_item->'itemId','description',v_item->'description'
      );
      if v_can_qty then
        v_filtered:=v_filtered||jsonb_build_object(
          'orderedQuantity',v_item->'orderedQuantity',
          'fulfilledQuantity',v_item->'fulfilledQuantity',
          'remainingQuantity',v_item->'remainingQuantity',
          'quantity',v_item->'quantity'
        );
      end if;
      if v_can_price then
        if p_module='sales' then
          v_filtered:=v_filtered||jsonb_build_object('unitPrice',v_item->'unitPrice');
        else
          v_filtered:=v_filtered||jsonb_build_object('unitCost',v_item->'unitCost');
        end if;
      end if;
      if v_can_item_wh and v_can_car_wh and v_item ? 'suggestedWarehouseId' then
        v_filtered:=v_filtered||jsonb_build_object('suggestedWarehouseId',v_item->'suggestedWarehouseId');
      end if;
      if v_can_item_wh and v_can_qty and v_can_inventory_qty and v_can_inventory_wh then
        v_filtered_balances:='[]'::jsonb;
        v_balances:=coalesce(v_item->'warehouseBalances','[]'::jsonb);
        for v_balance in select value from jsonb_array_elements(v_balances) loop
          v_filtered_balances:=v_filtered_balances||jsonb_build_array(jsonb_build_object(
            'warehouseId',v_balance->'warehouseId',
            'quantity',v_balance->'quantity',
            'reservedQuantity',v_balance->'reservedQuantity',
            'availableQuantity',v_balance->'availableQuantity'
          ));
        end loop;
        v_filtered:=v_filtered||jsonb_build_object('warehouseBalances',v_filtered_balances);
      else
        v_filtered:=v_filtered||jsonb_build_object('warehouseBalances','[]'::jsonb);
      end if;
      v_items:=v_items||jsonb_build_array(jsonb_strip_nulls(v_filtered));
    end loop;
  end if;

  if v_can_item_wh then
    for v_wh in select value from jsonb_array_elements(coalesce(v_context->'warehouses','[]'::jsonb)) loop
      v_filtered:=jsonb_build_object('id',v_wh->'id');
      if public.erp_cloud_user_can_view_field(p_company_id,'warehouses','name',null) then
        v_filtered:=v_filtered||jsonb_build_object('name',v_wh->'name');
      end if;
      if public.erp_cloud_user_can_view_field(p_company_id,'warehouses','code',null) then
        v_filtered:=v_filtered||jsonb_build_object('code',v_wh->'code');
      end if;
      if public.erp_cloud_user_can_view_field(p_company_id,'warehouses','address',null) then
        v_filtered:=v_filtered||jsonb_build_object('address',v_wh->'address');
      end if;
      if (v_filtered ? 'name') or (v_filtered ? 'code') then
        v_warehouses:=v_warehouses||jsonb_build_array(jsonb_strip_nulls(v_filtered));
      end if;
    end loop;
  end if;
  return jsonb_build_object('module',p_module,'orderId',p_order_id,'items',v_items,'warehouses',v_warehouses);
end;
$$;

revoke all on function public.erp_r92_workflow_action_allowed(uuid,text,text) from public,anon;
revoke all on function public.erp_r92_list_workflow_cash_accounts(uuid,text) from public,anon;
revoke all on function public.erp_r92_list_workflow_warehouses(uuid,text) from public,anon;
revoke all on function public.erp_r92_list_workflow_settlement_accounts(uuid,text) from public,anon;
revoke all on function public.erp_r92_get_commercial_order_allocation_context(uuid,uuid,text) from public,anon;
grant execute on function public.erp_r92_workflow_action_allowed(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r92_list_workflow_cash_accounts(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r92_list_workflow_warehouses(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r92_list_workflow_settlement_accounts(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r92_get_commercial_order_allocation_context(uuid,uuid,text) to authenticated,service_role;

-- Superseded unfiltered browser selectors become internal-only.
revoke all on function public.erp_r49_list_cloud_active_cash_accounts(uuid) from public,anon,authenticated;
revoke all on function public.erp_r49_list_cloud_active_warehouses(uuid) from public,anon,authenticated;
revoke all on function public.erp_list_cloud_settlement_accounts(uuid) from public,anon,authenticated;
revoke all on function public.erp_r49_get_commercial_order_allocation_context(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.erp_get_commercial_order_allocation_context(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_r49_list_cloud_active_cash_accounts(uuid) to service_role;
grant execute on function public.erp_r49_list_cloud_active_warehouses(uuid) to service_role;
grant execute on function public.erp_list_cloud_settlement_accounts(uuid) to service_role;
grant execute on function public.erp_r49_get_commercial_order_allocation_context(uuid,uuid,text) to service_role;
grant execute on function public.erp_get_commercial_order_allocation_context(uuid,uuid,text) to service_role;

-- ---------------------------------------------------------------------------
-- 5. Internal accounting repair/normalization routines are not browser APIs.
--    Operational invoice approval remains the only supported caller path.
-- ---------------------------------------------------------------------------
revoke all on function public.erp_v760_ensure_purchase_fx_settlement_accounts(uuid)
  from public,anon,authenticated;
revoke all on function public.erp_v760_normalize_purchase_invoice_posting(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.erp_v760_approve_workflow_invoice(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_v760_ensure_purchase_fx_settlement_accounts(uuid) to service_role;
grant execute on function public.erp_v760_normalize_purchase_invoice_posting(uuid,uuid) to service_role;
grant execute on function public.erp_v760_approve_workflow_invoice(uuid,uuid,text) to service_role;


-- ---------------------------------------------------------------------------
-- 6. Browser authority closure for internal accounting/payment engines.
--    These routines are implementation details behind the current R88/R90
--    permission-checked workflow APIs. Keeping them executable by the browser
--    would allow callers to bypass granular actions or mutate accounting master
--    state directly.
-- ---------------------------------------------------------------------------
revoke all on function public.erp_sync_accounting_master_data(uuid,jsonb,jsonb,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_ensure_fx_clearing_account(uuid,text)
  from public,anon,authenticated;
revoke all on function public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_apply_cloud_workflow_invoice_payment(uuid,uuid,text,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_v762_apply_workflow_payment(uuid,uuid,text,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_pay_cloud_sales_workflow_invoice(uuid,uuid,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_pay_cloud_purchase_workflow_invoice(uuid,uuid,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_pay_cloud_sales_workflow_invoice_batch(uuid,uuid,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_pay_cloud_purchase_workflow_invoice_batch(uuid,uuid,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_v737_record_maintenance_payment(uuid,uuid,jsonb)
  from public,anon,authenticated;

-- Superseded cash-transfer engines remain callable by owner/service code only.
-- The browser entry point is erp_r90_transfer_cloud_cash.
revoke all on function public.erp_transfer_cloud_cash_v2(uuid,text,text,numeric,numeric,numeric,timestamptz,text)
  from public,anon,authenticated;
revoke all on function public.erp_transfer_cloud_cash_v3(uuid,text,text,numeric,numeric,numeric,timestamptz,text)
  from public,anon,authenticated;
revoke all on function public.erp_transfer_cloud_cash_v4(uuid,text,text,numeric,numeric,numeric,timestamptz,text)
  from public,anon,authenticated;
revoke all on function public.erp_transfer_cloud_cash_v5(uuid,text,text,numeric,numeric,numeric,timestamptz,text)
  from public,anon,authenticated;
revoke all on function public.erp_v2300_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)
  from public,anon,authenticated;

grant execute on function public.erp_sync_accounting_master_data(uuid,jsonb,jsonb,jsonb) to service_role;
grant execute on function public.erp_ensure_fx_clearing_account(uuid,text) to service_role;
grant execute on function public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb) to service_role;
grant execute on function public.erp_apply_cloud_workflow_invoice_payment(uuid,uuid,text,jsonb) to service_role;
grant execute on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) to service_role;
grant execute on function public.erp_v762_apply_workflow_payment(uuid,uuid,text,jsonb) to service_role;
grant execute on function public.erp_pay_cloud_sales_workflow_invoice(uuid,uuid,jsonb) to service_role;
grant execute on function public.erp_pay_cloud_purchase_workflow_invoice(uuid,uuid,jsonb) to service_role;
grant execute on function public.erp_pay_cloud_sales_workflow_invoice_batch(uuid,uuid,jsonb) to service_role;
grant execute on function public.erp_pay_cloud_purchase_workflow_invoice_batch(uuid,uuid,jsonb) to service_role;
grant execute on function public.erp_v737_record_maintenance_payment(uuid,uuid,jsonb) to service_role;
grant execute on function public.erp_transfer_cloud_cash_v2(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to service_role;
grant execute on function public.erp_transfer_cloud_cash_v3(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to service_role;
grant execute on function public.erp_transfer_cloud_cash_v4(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to service_role;
grant execute on function public.erp_transfer_cloud_cash_v5(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to service_role;
grant execute on function public.erp_v2300_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to service_role;


-- ---------------------------------------------------------------------------
-- 7. Professional-accounting reads must not bypass Accounting/Periods access
--    through direct table SELECT. Restrictive policies preserve Realtime for
--    authorized users while making REST/Data API fail closed for everyone else.
-- ---------------------------------------------------------------------------
drop policy if exists erp_r92_cost_centers_select_guard on public.erp_cost_centers;
create policy erp_r92_cost_centers_select_guard on public.erp_cost_centers
  as restrictive for select to authenticated
  using (public.erp_cloud_user_has_permission(company_id,'accounting.view'));

drop policy if exists erp_r92_accounting_projects_select_guard on public.erp_accounting_projects;
create policy erp_r92_accounting_projects_select_guard on public.erp_accounting_projects
  as restrictive for select to authenticated
  using (public.erp_cloud_user_has_permission(company_id,'accounting.view'));

drop policy if exists erp_r92_fiscal_years_select_guard on public.erp_fiscal_years;
create policy erp_r92_fiscal_years_select_guard on public.erp_fiscal_years
  as restrictive for select to authenticated
  using (
    public.erp_cloud_user_has_permission(company_id,'accounting.view')
    or public.erp_cloud_user_has_permission(company_id,'periods.view')
  );

drop policy if exists erp_r92_fiscal_periods_select_guard on public.erp_fiscal_periods;
create policy erp_r92_fiscal_periods_select_guard on public.erp_fiscal_periods
  as restrictive for select to authenticated
  using (
    public.erp_cloud_user_has_permission(company_id,'accounting.view')
    or public.erp_cloud_user_has_permission(company_id,'periods.view')
  );

create or replace function public.erp_r92_list_professional_accounting_records(
  p_company_id uuid,p_kind text,p_parent_id text default null
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_kind text:=lower(btrim(coalesce(p_kind,'')));
begin
  perform public.erp_active_company_context(p_company_id);
  if v_kind in ('fiscal_years','fiscal_periods') then
    if not (
      public.erp_cloud_user_has_permission(p_company_id,'accounting.view')
      or public.erp_cloud_user_has_permission(p_company_id,'periods.view')
    ) then
      raise exception 'permission_denied:periods.view' using errcode='42501';
    end if;
  elsif v_kind in ('cost_centers','accounting_projects') then
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then
      raise exception 'permission_denied:accounting.view' using errcode='42501';
    end if;
  else
    raise exception 'invalid_professional_accounting_record_kind:%',p_kind using errcode='22023';
  end if;

  if v_kind='fiscal_years' then
    return query
      select y.data
      from public.erp_fiscal_years y
      where y.company_id=p_company_id and not y.is_deleted
      order by public.erp_try_timestamptz(y.data->>'startDate',y.created_at) desc,y.id;
  elsif v_kind='fiscal_periods' then
    return query
      select p.data
      from public.erp_fiscal_periods p
      where p.company_id=p_company_id and not p.is_deleted
        and (p_parent_id is null or p.data->>'fiscalYearId'=p_parent_id)
      order by public.erp_try_numeric(p.data->>'periodNumber',0),p.id;
  elsif v_kind='cost_centers' then
    return query
      select c.data
      from public.erp_cost_centers c
      where c.company_id=p_company_id and not c.is_deleted
      order by coalesce(c.data->>'code',''),c.id;
  else
    return query
      select p.data
      from public.erp_accounting_projects p
      where p.company_id=p_company_id and not p.is_deleted
      order by coalesce(p.data->>'code',''),p.id;
  end if;
end;
$$;

create or replace function public.erp_r92_list_accounting_branches(p_company_id uuid)
returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_rows jsonb; v_row jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then
    raise exception 'permission_denied:accounting.view' using errcode='42501';
  end if;
  v_rows:=coalesce(public.erp_list_cloud_branches(),'[]'::jsonb);
  for v_row in select value from jsonb_array_elements(v_rows) loop
    return next v_row;
  end loop;
  return;
end;
$$;

revoke all on function public.erp_r92_list_professional_accounting_records(uuid,text,text) from public,anon;
revoke all on function public.erp_r92_list_accounting_branches(uuid) from public,anon;
grant execute on function public.erp_r92_list_professional_accounting_records(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r92_list_accounting_branches(uuid) to authenticated,service_role;


-- ---------------------------------------------------------------------------
-- 8. Superseded module mutation RPCs are internal only.
--    Current browser entry points are the R15/R22/R49/R67/R88/R90/R92
--    permission-checked APIs used by Flutter. Historical implementations remain
--    callable by owner/service code so forward-only migrations and internal
--    workflow delegation keep working, but cannot be invoked directly over
--    PostgREST by an authenticated user.
-- ---------------------------------------------------------------------------
do $$
declare
  v_name text;
  v_proc regprocedure;
begin
  foreach v_name in array array[
    -- Commercial workflow generations superseded by R49/R88.
    'erp_approve_cloud_purchase_receipt',
    'erp_approve_cloud_purchase_workflow_invoice',
    'erp_approve_cloud_sales_delivery',
    'erp_approve_cloud_sales_workflow_invoice',
    'erp_approve_cloud_workflow_invoice',
    'erp_approve_invoice_cloud',
    'erp_create_cloud_purchase_order',
    'erp_create_cloud_sales_order',
    'erp_delete_cloud_purchase_order',
    'erp_delete_cloud_purchase_order_v2',
    'erp_delete_cloud_purchase_order_v3',
    'erp_delete_cloud_sales_order',
    'erp_delete_cloud_sales_order_v2',
    'erp_delete_cloud_sales_order_v3',
    'erp_delete_cloud_sales_order_v4',
    'erp_manage_commercial_order_component',
    'erp_manage_commercial_order_component_v2',
    'erp_phase2_post_sales_delivery',
    'erp_prepare_commercial_order_delete_keep_payments',
    'erp_reopen_cloud_purchase_order',
    'erp_reopen_cloud_sales_order',
    'erp_restore_commercial_order_links',
    'erp_reverse_cloud_workflow_invoice_payments',
    'erp_reverse_invoice_cloud',
    'erp_reverse_workflow_cloud',
    'erp_update_cloud_purchase_order_with_links',
    'erp_update_cloud_sales_order_with_links',
    'erp_v750_approve_workflow_invoice_resilient',
    'erp_v761_approve_workflow_invoice',
    'erp_v762_approve_workflow_invoice',
    'erp_v765_approve_invoice_safe',
    'erp_v765_approve_purchase_invoice_safe',
    'erp_v765_approve_sales_invoice_safe',
    'erp_v767_approve_invoice_safe',
    'erp_v767_approve_purchase_invoice_safe',
    'erp_v767_approve_sales_invoice_safe',

    -- Inventory/car generations superseded by the R49 guarded repositories.
    'erp_create_car_warehouse_transfer',
    'erp_create_car_warehouse_transfer_batch',
    'erp_delete_inventory_warehouse_transfer',
    'erp_phase2_post_scrap',
    'erp_post_scrap_warehouse_value',
    'erp_reverse_inventory_document_cloud',
    'erp_transfer_inventory_stock_batch',
    'erp_update_car_warehouse_transfer',

    -- Accounting generations superseded by R15/R22/R49/R90 browser APIs.
    'erp_delete_cloud_manual_journal',
    'erp_post_financial_event',
    'erp_post_payment_cloud',
    'erp_prepare_payment_settlement',
    'erp_post_fixed_asset_depreciation',
    'erp_r14_approve_purchase_invoice',
    'erp_r14_approve_sales_invoice',
    'erp_r14_approve_workflow_invoice',
    'erp_r14_soft_delete_cloud_master_record',
    'erp_r14_upsert_cloud_master_record',
    'erp_r15_rebind_cashbox_journals',
    'erp_r15_reconcile_company_state',
    'erp_r15_transfer_cloud_cash',
    'erp_r16_reconcile_company_state',
    'erp_r22_approve_workflow_invoice',
    'erp_r22_save_cloud_cash_account',
    'erp_r27_save_cash_account',
    'erp_r28_save_cash_account',
    'erp_r9_post_cloud_cash_transaction',
    'erp_r9_save_cloud_cash_account',
    'erp_r9_soft_delete_cloud_master_record',
    'erp_r9_transfer_cloud_cash',
    'erp_r9_upsert_cloud_master_record',
    'erp_v65_soft_delete_journal',

    -- Opportunity synchronization is trigger/workflow-owned, never a client API.
    'erp_sync_opportunity_from_sales_order',
    'erp_sync_opportunity_sales_lifecycle'
  ] loop
    for v_proc in
      select p.oid::regprocedure
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop
      execute format('revoke all on function %s from public,anon,authenticated',v_proc);
      execute format('grant execute on function %s to service_role',v_proc);
    end loop;
  end loop;
end $$;

commit;
