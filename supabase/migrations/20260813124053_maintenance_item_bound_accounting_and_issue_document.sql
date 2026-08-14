begin;

-- Maintenance uses the same definition-owned bindings as commercial posting,
-- but fails closed instead of manufacturing or falling back to generic item
-- accounts. The generic maintenance revenue binding remains exclusively the
-- configured residual labor binding.
create or replace function public.erp_maintenance_bound_accounts(
  p_company_id uuid,
  p_item_id text,
  p_currency text,
  p_service boolean default false
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  d jsonb;
  c text:=upper(coalesce(nullif(btrim(p_currency),''),'USD'));
  revenue_id text;
  asset_id text;
  cost_id text;
begin
  d:=public.erp_v764_definition_data(p_company_id,'product',p_item_id);
  if d is null then raise exception 'maintenance_item_not_found:%',p_item_id; end if;
  if public.erp_v764_definition_currency(p_company_id,'product',p_item_id)<>c then
    raise exception 'maintenance_item_currency_mismatch:%:%',p_item_id,c;
  end if;
  revenue_id:=nullif(coalesce(
    case when c='USD' then coalesce(d->>'salesRevenueUsdAccountId',d->>'sales_revenue_usd_account_id')
         when c='IQD' then coalesce(d->>'salesRevenueIqdAccountId',d->>'sales_revenue_iqd_account_id') end,
    d->>'salesRevenueAccountId',d->>'sales_revenue_account_id'), '');
  if revenue_id is null then
    if p_service then raise exception 'maintenance_service_revenue_account_missing:%',p_item_id;
    else raise exception 'maintenance_material_revenue_account_missing:%',p_item_id; end if;
  end if;
  perform public.erp_phase2_account_guard(p_company_id,revenue_id,'revenue',c);

  if not p_service then
    asset_id:=nullif(coalesce(d->>'inventoryAssetAccountId',d->>'inventory_asset_account_id'),'');
    cost_id:=nullif(coalesce(d->>'salesCostExpenseAccountId',d->>'sales_cost_expense_account_id',
      d->>'costOfSalesAccountId',d->>'costOfSaleAccountId',
      d->>'cost_of_sales_account_id',d->>'cost_of_sale_account_id'),'');
    if asset_id is null then raise exception 'maintenance_material_inventory_account_missing:%',p_item_id; end if;
    if cost_id is null then raise exception 'maintenance_material_cost_account_missing:%',p_item_id; end if;
    perform public.erp_phase2_account_guard(p_company_id,asset_id,'asset',c);
    perform public.erp_phase2_account_guard(p_company_id,cost_id,'expense',c);
  end if;
  return jsonb_build_object('currency',c,'revenueAccountId',revenue_id,
    'assetAccountId',asset_id,'costExpenseAccountId',cost_id);
end;
$$;

revoke all on function public.erp_maintenance_bound_accounts(uuid,text,text,boolean)
  from public,anon,authenticated;
grant execute on function public.erp_maintenance_bound_accounts(uuid,text,text,boolean)
  to service_role;

create or replace function public.erp_v736_post_maintenance_invoice(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  p record;
  f record;
  ac jsonb;
  defaults jsonb;
  v_currency text;
  v_effective timestamptz;
  v_partner_account text;
  v_labor_revenue_account text;
  v_revenue_lines jsonb:='[]'::jsonb;
  v_cost_lines jsonb:='[]'::jsonb;
  v_entry text;
  v_cost_entry text;
  v_entries jsonb:='[]'::jsonb;
  v_line_amount numeric;
  v_bound_billing numeric:=0;
  v_labor_amount numeric;
  v_total_fifo_cost numeric:=0;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.invoice_journal_entry_id is not null then
    return jsonb_build_object('journalEntryId',o.invoice_journal_entry_id,
      'costJournalEntries',o.cost_journal_entry_ids,'capitalizationApplied',false,
      'fifoValuationApplied',true,'accountingOwner','invoice_item_bindings');
  end if;
  if o.pricing_type<>'paid' or o.sale_price<=0 then raise exception 'paid_maintenance_invoice_required'; end if;
  if o.customer_id is null then raise exception 'paid_maintenance_customer_required'; end if;
  v_currency:=upper(coalesce(o.currency_code,''));
  if v_currency not in ('USD','IQD') then raise exception 'maintenance_currency_invalid:%',v_currency; end if;
  v_effective:=coalesce(o.maintenance_date,now());
  perform public.erp_validate_operational_date(p_company_id,'maintenance',v_effective);
  perform public.erp_v764_assert_partner_dual_ledgers(p_company_id,o.customer_id::text,'customer');
  v_partner_account:=public.erp_workflow_partner_account(
    p_company_id,'customer',o.customer_id::text,v_currency);
  if v_partner_account is null then raise exception 'maintenance_receivable_account_missing'; end if;
  perform public.erp_phase2_account_guard(p_company_id,v_partner_account,'asset',v_currency);
  v_revenue_lines:=jsonb_build_array(jsonb_build_object(
    'accountId',v_partner_account,'debit',o.sale_price,'credit',0,'currency',v_currency,
    'description','Maintenance invoice receivable','maintenanceOrderId',p_order_id,
    'invoiceNumber',o.invoice_number));

  for p in select * from public.erp_maintenance_parts
    where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted
    order by id
  loop
    ac:=public.erp_maintenance_bound_accounts(p_company_id,
      coalesce(p.source_product_id,p.product_id::text),v_currency,p.line_type='service');
    v_line_amount:=round(coalesce(p.line_total_price,p.unit_price*p.quantity,0),2);
    if v_line_amount<0 then raise exception 'maintenance_line_billing_invalid:%',p.id; end if;
    if v_line_amount>0 then
      v_revenue_lines:=v_revenue_lines||jsonb_build_array(jsonb_build_object(
        'accountId',ac->>'revenueAccountId','debit',0,'credit',v_line_amount,
        'currency',v_currency,
        'description',case when p.line_type='service' then 'Maintenance service - ' else 'Maintenance material - ' end||p.product_name,
        'itemId',coalesce(p.source_product_id,p.product_id::text),'maintenanceLineId',p.id,
        'quantity',p.quantity,'unitPrice',p.unit_price));
      v_bound_billing:=v_bound_billing+v_line_amount;
    end if;
  end loop;
  if v_bound_billing>o.sale_price+0.01 then
    raise exception 'maintenance_invoice_line_total_exceeds_invoice:%:%',v_bound_billing,o.sale_price;
  end if;
  v_labor_amount:=round(greatest(o.sale_price-v_bound_billing,0),2);
  if v_labor_amount>0 then
    defaults:=public.erp_v736_ensure_currency_revenue_accounts(p_company_id);
    v_labor_revenue_account:=case when v_currency='IQD'
      then defaults->>'maintenanceRevenueIqdAccountId'
      else defaults->>'maintenanceRevenueUsdAccountId' end;
    if v_labor_revenue_account is null then raise exception 'maintenance_labor_revenue_account_missing'; end if;
    perform public.erp_phase2_account_guard(p_company_id,v_labor_revenue_account,'revenue',v_currency);
    v_revenue_lines:=v_revenue_lines||jsonb_build_array(jsonb_build_object(
      'accountId',v_labor_revenue_account,'debit',0,'credit',v_labor_amount,
      'currency',v_currency,'description','Maintenance labor',
      'maintenanceOrderId',p_order_id));
  end if;

  v_entry:=public.erp_phase2_insert_journal_at(
    p_company_id,'maintenance_invoice_revenue',p_order_id::text,
    public.erp_next_document_number(p_company_id,'maintenance_invoice_journal','MIJ',v_effective),
    'Maintenance invoice '||coalesce(o.invoice_number,o.order_number),v_currency,
    v_revenue_lines,v_effective);

  for f in
    select fc.item_id,sum(fc.total_cost) actual_cost,sum(fc.quantity) quantity
    from public.erp_inventory_fifo_consumptions fc
    join public.erp_inventory_cost_layers layer on layer.id=fc.layer_id
      and layer.company_id=fc.company_id
    where fc.company_id=p_company_id and fc.sales_order_id=p_order_id
      and fc.status='active' and fc.item_type='product'
      and upper(layer.currency)=v_currency
    group by fc.item_id
    order by fc.item_id
  loop
    ac:=public.erp_maintenance_bound_accounts(p_company_id,f.item_id,v_currency,false);
    if f.actual_cost>0 then
      v_cost_lines:=v_cost_lines||jsonb_build_array(
        jsonb_build_object('accountId',ac->>'costExpenseAccountId','debit',f.actual_cost,'credit',0,
          'currency',v_currency,'description','Maintenance FIFO material cost','itemId',f.item_id,
          'quantity',f.quantity,'maintenanceOrderId',p_order_id),
        jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',f.actual_cost,
          'currency',v_currency,'description','Maintenance FIFO inventory issue','itemId',f.item_id,
          'quantity',f.quantity,'maintenanceOrderId',p_order_id));
      v_total_fifo_cost:=v_total_fifo_cost+f.actual_cost;
    end if;
  end loop;
  if jsonb_array_length(v_cost_lines)>0 then
    v_cost_entry:=public.erp_phase2_insert_journal_at(
      p_company_id,'maintenance_invoice_cost_'||lower(v_currency),p_order_id::text,
      public.erp_next_document_number(p_company_id,'maintenance_cost_journal_'||lower(v_currency),'MIC-'||v_currency,v_effective),
      'Maintenance invoice FIFO material cost',v_currency,v_cost_lines,v_effective);
    v_entries:=jsonb_build_array(jsonb_build_object('currency',v_currency,'journalEntryId',v_cost_entry));
    update public.erp_inventory_fifo_consumptions set journal_entry_id=v_cost_entry
      where company_id=p_company_id and sales_order_id=p_order_id
        and status='active' and item_type='product';
  end if;

  update public.erp_maintenance_orders set invoice_journal_entry_id=v_entry,
    cost_journal_entry_ids=v_entries,car_cost_added=0,
    accounting_payload=accounting_payload||jsonb_build_object(
      'accountingOwner','invoice_item_bindings','actualFifoCost',round(v_total_fifo_cost,6),
      'boundLineBilling',round(v_bound_billing,2),'laborBilling',v_labor_amount,
      'carCostAdded',0,'capitalizationApplied',false,'capitalizationPolicy','disabled',
      'postedAt',now(),'effectiveAt',v_effective,'invoiceCurrency',v_currency),updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  return jsonb_build_object('journalEntryId',v_entry,'costJournalEntries',v_entries,
    'capitalizationApplied',false,'fifoValuationApplied',true,
    'fifoValuationOwner','material_issue_event','accountingOwner','invoice_item_bindings',
    'effectiveAt',v_effective);
end;
$$;

revoke all on function public.erp_v736_post_maintenance_invoice(uuid,uuid)
  from public,anon;
grant execute on function public.erp_v736_post_maintenance_invoice(uuid,uuid)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
