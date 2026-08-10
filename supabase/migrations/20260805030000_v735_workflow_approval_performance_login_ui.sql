-- Quality Line ERP 18.9.5 / V7.3.5
-- Repair commercial and maintenance approval chains when legacy items do not
-- yet carry explicit inventory/cost accounts. The repair provisions isolated
-- MULTI-currency operational fallbacks and persists the resolved bindings so
-- future approvals stay deterministic.

create or replace function public.erp_v735_ensure_operational_accounts(
  p_company_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asset_parent text;
  v_expense_parent text;
  v_inventory_id text := 'v735-inventory-' || substr(md5(p_company_id::text),1,16);
  v_cost_id text := 'v735-cost-' || substr(md5(p_company_id::text),1,16);
  v_maintenance_id text := 'v735-maintenance-' || substr(md5(p_company_id::text),1,16);
begin
  perform public.erp_seed_default_accounts(p_company_id);

  select a.account_id into v_asset_parent
  from public.erp_accounts a
  where a.organization_id = p_company_id
    and a.code = '1300'
    and a.is_active
  limit 1;

  select a.account_id into v_expense_parent
  from public.erp_accounts a
  where a.organization_id = p_company_id
    and a.code = '5000'
    and a.is_active
  limit 1;

  if v_asset_parent is null or v_expense_parent is null then
    raise exception 'operational_account_parents_missing';
  end if;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,
    currency,opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values (
    p_company_id,v_inventory_id,'1390','المخزون التشغيلي العام','asset',
    v_asset_parent,'MULTI',0,true,now(),now(),auth.uid()
  )
  on conflict (organization_id,code) do update set
    name = excluded.name,
    account_type = excluded.account_type,
    parent_account_id = excluded.parent_account_id,
    currency = 'MULTI',
    is_active = true,
    synced_at = now(),
    synced_by = auth.uid()
  returning account_id into v_inventory_id;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,
    currency,opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values (
    p_company_id,v_cost_id,'5190','تكلفة المبيعات التشغيلية','expense',
    v_expense_parent,'MULTI',0,true,now(),now(),auth.uid()
  )
  on conflict (organization_id,code) do update set
    name = excluded.name,
    account_type = excluded.account_type,
    parent_account_id = excluded.parent_account_id,
    currency = 'MULTI',
    is_active = true,
    synced_at = now(),
    synced_by = auth.uid()
  returning account_id into v_cost_id;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,
    currency,opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values (
    p_company_id,v_maintenance_id,'5290','مصروفات الصيانة التشغيلية','expense',
    v_expense_parent,'MULTI',0,true,now(),now(),auth.uid()
  )
  on conflict (organization_id,code) do update set
    name = excluded.name,
    account_type = excluded.account_type,
    parent_account_id = excluded.parent_account_id,
    currency = 'MULTI',
    is_active = true,
    synced_at = now(),
    synced_by = auth.uid()
  returning account_id into v_maintenance_id;

  return jsonb_build_object(
    'inventoryAssetAccountId',v_inventory_id,
    'costExpenseAccountId',v_cost_id,
    'maintenanceExpenseAccountId',v_maintenance_id
  );
end;
$$;

create or replace function public.erp_v735_account_usable(
  p_company_id uuid,
  p_account_id text,
  p_expected_type text,
  p_currency text default null
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.erp_accounts a
    where a.organization_id = p_company_id
      and a.account_id = nullif(btrim(p_account_id),'')
      and a.is_active
      and lower(coalesce(a.account_type,'')) = lower(p_expected_type)
      and (
        p_currency is null
        or upper(coalesce(a.currency,'MULTI')) = 'MULTI'
        or upper(coalesce(a.currency,'')) = upper(p_currency)
      )
  );
$$;

create or replace function public.erp_phase2_item_accounts(
  p_company_id uuid,
  p_item_type text,
  p_item_id text,
  p_currency text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_data jsonb;
  v_defaults jsonb;
  v_asset_id text;
  v_expense_id text;
  v_currency text := upper(coalesce(nullif(btrim(p_currency),''),'USD'));
  v_patch jsonb;
begin
  if lower(btrim(p_item_type)) = 'car' then
    select c.data into v_data
    from public.erp_cars c
    where c.company_id = p_company_id
      and c.id = p_item_id
      and not c.is_deleted;
  else
    select i.data into v_data
    from public.erp_inventory i
    where i.company_id = p_company_id
      and i.id = p_item_id
      and not i.is_deleted;
  end if;

  if v_data is null then raise exception 'inventory_item_not_found:%',p_item_id; end if;
  if lower(coalesce(v_data->>'itemType',v_data->>'item_type','stock')) = 'service' then
    raise exception 'service_item_has_no_inventory_posting:%',p_item_id;
  end if;

  v_defaults := public.erp_v735_ensure_operational_accounts(p_company_id);
  v_asset_id := nullif(coalesce(
    v_data->>'inventoryAssetAccountId',
    v_data->>'inventory_asset_account_id'
  ),'');
  v_expense_id := nullif(coalesce(
    v_data->>'costOfSalesAccountId',
    v_data->>'costOfSaleAccountId',
    v_data->>'cost_of_sales_account_id',
    v_data->>'cost_of_sale_account_id'
  ),'');

  if not public.erp_v735_account_usable(
    p_company_id,v_asset_id,'asset',v_currency
  ) then
    v_asset_id := v_defaults->>'inventoryAssetAccountId';
  end if;
  if not public.erp_v735_account_usable(
    p_company_id,v_expense_id,'expense',v_currency
  ) then
    v_expense_id := v_defaults->>'costExpenseAccountId';
  end if;

  perform public.erp_phase2_account_guard(
    p_company_id,v_asset_id,'asset',v_currency
  );
  perform public.erp_phase2_account_guard(
    p_company_id,v_expense_id,'expense',v_currency
  );

  v_patch := jsonb_build_object(
    'inventoryAssetAccountId',v_asset_id,
    'inventory_asset_account_id',v_asset_id,
    'costOfSalesAccountId',v_expense_id,
    'costOfSaleAccountId',v_expense_id,
    'cost_of_sales_account_id',v_expense_id,
    'cost_of_sale_account_id',v_expense_id,
    'accountBindingsRepairedAt',now()
  );

  if lower(btrim(p_item_type)) = 'car' then
    update public.erp_cars
       set data = data || v_patch,
           updated_at = now(),
           updated_by = auth.uid()
     where company_id = p_company_id
       and id = p_item_id
       and not is_deleted
       and (
         coalesce(data->>'inventoryAssetAccountId','') <> v_asset_id
         or coalesce(data->>'costOfSalesAccountId','') <> v_expense_id
       );
  else
    update public.erp_inventory
       set data = data || v_patch,
           updated_at = now(),
           updated_by = auth.uid()
     where company_id = p_company_id
       and id = p_item_id
       and not is_deleted
       and (
         coalesce(data->>'inventoryAssetAccountId','') <> v_asset_id
         or coalesce(data->>'costOfSalesAccountId','') <> v_expense_id
       );
  end if;

  return jsonb_build_object(
    'assetAccountId',v_asset_id,
    'costExpenseAccountId',v_expense_id
  );
end;
$$;

create or replace function public.erp_phase2_post_purchase_receipt(
  p_company_id uuid,
  p_receipt_id uuid
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_order public.erp_purchase_orders_cloud%rowtype;
  v_line record;
  v_accounts jsonb;
  v_supplier_account text;
  v_journal_lines jsonb := '[]'::jsonb;
  v_total numeric := 0;
  v_amount numeric;
  v_entry_id text;
  v_existing_entry text;
  v_effective timestamptz;
begin
  select * into v_doc
  from public.erp_commercial_workflow_documents
  where company_id = p_company_id
    and id = p_receipt_id
    and module = 'purchases'
    and document_type = 'receipt'
    and not is_deleted;
  if not found or v_doc.status <> 'approved' then
    raise exception 'purchase_receipt_must_be_approved';
  end if;

  v_existing_entry := nullif(v_doc.payload->>'inventoryJournalEntryId','');
  if v_existing_entry is not null and exists(
    select 1 from public.erp_journal_entries e
    where e.company_id = p_company_id
      and e.id = v_existing_entry
      and not e.is_deleted
  ) then
    return v_existing_entry;
  end if;

  select * into v_order
  from public.erp_purchase_orders_cloud
  where company_id = p_company_id
    and id = v_doc.parent_id
    and not is_deleted;
  if not found then raise exception 'linked_purchase_order_not_found'; end if;

  perform public.erp_v735_ensure_operational_accounts(p_company_id);
  v_effective := coalesce(
    v_doc.effective_at,v_order.effective_at,v_doc.created_at,now()
  );
  v_supplier_account := public.erp_workflow_partner_account(
    p_company_id,'supplier',v_order.supplier_id,v_order.currency
  );
  perform public.erp_phase2_account_guard(
    p_company_id,v_supplier_account,'liability',v_order.currency
  );

  for v_line in
    select x.item_type,x.item_id,x.description,x.quantity,x.unit_cost
    from public.erp_purchase_order_items_cloud x
    where x.company_id = p_company_id
      and x.order_id = v_order.id
      and not x.is_deleted
  loop
    v_accounts := public.erp_phase2_item_accounts(
      p_company_id,v_line.item_type,v_line.item_id,v_order.currency
    );
    v_amount := v_line.quantity * v_line.unit_cost;
    v_total := v_total + v_amount;
    v_journal_lines := v_journal_lines || jsonb_build_array(
      jsonb_build_object(
        'accountId',v_accounts->>'assetAccountId',
        'debit',v_amount,
        'credit',0,
        'description','إثبات استلام ' || v_line.description,
        'itemType',v_line.item_type,
        'itemId',v_line.item_id
      )
    );
  end loop;

  v_journal_lines := v_journal_lines || jsonb_build_array(
    jsonb_build_object(
      'accountId',v_supplier_account,
      'debit',0,
      'credit',v_total,
      'description','ذمة المورد'
    )
  );

  v_entry_id := public.erp_phase2_insert_journal_at(
    p_company_id,
    'purchases_inventory',
    p_receipt_id::text,
    'PINV-' || replace(p_receipt_id::text,'-',''),
    'قيد إشعار استلام المشتريات ' || v_doc.document_number,
    v_order.currency,
    v_journal_lines,
    v_effective
  );

  update public.erp_commercial_workflow_documents
     set effective_at = v_effective,
         payload = payload || jsonb_build_object(
           'inventoryJournalEntryId',v_entry_id,
           'accountingPostedAt',now(),
           'effectiveAt',v_effective,
           'accountBindingsVerifiedAt',now()
         ),
         updated_at = now()
   where id = p_receipt_id;
  return v_entry_id;
end;
$$;

create or replace function public.erp_phase3_post_maintenance_issue(
  p_company_id uuid,
  p_order_id uuid
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_part record;
  v_accounts jsonb;
  v_defaults jsonb;
  v_lines jsonb := '[]'::jsonb;
  v_amount numeric;
  v_entry_id text;
  v_product_id text;
  v_expense_account text;
  v_currency text;
begin
  select * into v_order
  from public.erp_maintenance_orders
  where company_id = p_company_id
    and id = p_order_id
    and not is_deleted;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  v_currency := upper(coalesce(nullif(btrim(v_order.currency_code),''),'USD'));
  v_defaults := public.erp_v735_ensure_operational_accounts(p_company_id);
  v_expense_account := nullif(btrim(v_order.maintenance_expense_account_id),'');
  if not public.erp_v735_account_usable(
    p_company_id,v_expense_account,'expense',v_currency
  ) then
    v_expense_account := v_defaults->>'maintenanceExpenseAccountId';
    update public.erp_maintenance_orders
       set maintenance_expense_account_id = v_expense_account,
           updated_at = now()
     where company_id = p_company_id and id = p_order_id;
  end if;
  perform public.erp_phase2_account_guard(
    p_company_id,v_expense_account,'expense',v_currency
  );

  for v_part in
    select * from public.erp_maintenance_parts
    where company_id = p_company_id
      and maintenance_order_id = p_order_id
      and not is_deleted
      and line_type <> 'service'
  loop
    v_product_id := coalesce(v_part.source_product_id,v_part.product_id::text);
    v_amount := v_part.quantity * v_part.unit_cost;
    v_accounts := public.erp_phase2_item_accounts(
      p_company_id,'product',v_product_id,v_currency
    );
    if v_amount > 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object(
          'accountId',v_expense_account,
          'debit',v_amount,
          'credit',0,
          'description','كلفة صيانة - ' || v_part.product_name,
          'itemId',v_product_id
        ),
        jsonb_build_object(
          'accountId',v_accounts->>'assetAccountId',
          'debit',0,
          'credit',v_amount,
          'description','إخراج مخزون للصيانة - ' || v_part.product_name,
          'itemId',v_product_id
        )
      );
    end if;
  end loop;

  if jsonb_array_length(v_lines) = 0 then return null; end if;
  v_entry_id := public.erp_phase2_insert_journal(
    p_company_id,
    'maintenance_stock_issue',
    p_order_id::text,
    public.erp_next_document_number(
      p_company_id,'maintenance_journal','MJE',v_order.maintenance_date
    ),
    'قيد مواد أمر الصيانة ' || v_order.order_number,
    v_currency,
    v_lines
  );
  return v_entry_id;
end;
$$;

-- Existing business RPCs retain their permissions after CREATE OR REPLACE.
-- The two repair helpers remain internal to security-definer workflow RPCs.
revoke all on function public.erp_v735_ensure_operational_accounts(uuid)
  from public,anon,authenticated;
revoke all on function public.erp_v735_account_usable(uuid,text,text,text)
  from public,anon,authenticated;
grant execute on function public.erp_v735_ensure_operational_accounts(uuid)
  to service_role;
grant execute on function public.erp_v735_account_usable(uuid,text,text,text)
  to service_role;
