-- Quality Line ERP 22.9.7 / V7.6.7 final invoice/export runtime closure.
begin;

create or replace function public.erp_v767_assert_partner_ledgers(
  p_company_id uuid,p_partner_id text,p_partner_type text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare usd_id text; iqd_id text; expected_type text;
begin
  expected_type:=case when lower(p_partner_type)='customer' then 'asset' else 'liability' end;
  usd_id:=public.erp_workflow_partner_account(p_company_id,lower(p_partner_type),p_partner_id,'USD');
  iqd_id:=public.erp_workflow_partner_account(p_company_id,lower(p_partner_type),p_partner_id,'IQD');
  perform public.erp_phase2_account_guard(p_company_id,usd_id,expected_type,'USD');
  perform public.erp_phase2_account_guard(p_company_id,iqd_id,expected_type,'IQD');
  return jsonb_build_object('usdAccountId',usd_id,'iqdAccountId',iqd_id);
end; $$;

create or replace function public.erp_v767_invoice_policy_preflight(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  partner_id text; c text; partner_account text; r record; ac jsonb;
  item_currency text; item_kind text; cost_currency text;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module:%',p_module; end if;
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  c:=upper(coalesce(d.payload->>'currency',''));
  if c not in ('USD','IQD') then raise exception 'workflow_invoice_currency_invalid:%',c; end if;

  if p_module='sales' then
    select customer_id into partner_id from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=d.parent_id and not is_deleted;
    if partner_id is null then raise exception 'sales_customer_missing'; end if;
    perform public.erp_v767_assert_partner_ledgers(p_company_id,partner_id,'customer');
    partner_account:=public.erp_workflow_partner_account(p_company_id,'customer',partner_id,c);
    perform public.erp_phase2_account_guard(p_company_id,partner_account,'asset',c);

    for r in select item_type,item_id,description from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted loop
      item_currency:=public.erp_v764_definition_currency(p_company_id,r.item_type,r.item_id);
      if item_currency<>c then raise exception 'sales_item_currency_mismatch:%:%:%',r.item_id,item_currency,c; end if;
      ac:=public.erp_v764_definition_accounts(p_company_id,r.item_type,r.item_id);
      perform public.erp_phase2_account_guard(p_company_id,ac->>'revenueAccountId','revenue',c);
      item_kind:=lower(coalesce((public.erp_v764_definition_data(p_company_id,r.item_type,r.item_id))->>'itemType',
                                (public.erp_v764_definition_data(p_company_id,r.item_type,r.item_id))->>'item_type','stock'));
      if item_kind<>'service' then
        perform public.erp_phase2_account_guard(p_company_id,ac->>'assetAccountId','asset',c);
        perform public.erp_phase2_account_guard(p_company_id,ac->>'costExpenseAccountId','expense',c);
      end if;
    end loop;
  else
    select supplier_id into partner_id from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=d.parent_id and not is_deleted;
    if partner_id is null then raise exception 'purchase_supplier_missing'; end if;
    perform public.erp_v767_assert_partner_ledgers(p_company_id,partner_id,'supplier');
    partner_account:=public.erp_workflow_partner_account(p_company_id,'supplier',partner_id,c);
    perform public.erp_phase2_account_guard(p_company_id,partner_account,'liability',c);

    for r in select item_type,item_id,description from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted loop
      item_currency:=public.erp_v764_definition_currency(p_company_id,r.item_type,r.item_id);
      if item_currency<>c then raise exception 'purchase_item_currency_mismatch:%:%:%',r.item_id,item_currency,c; end if;
      ac:=public.erp_v764_definition_accounts(p_company_id,r.item_type,r.item_id);
      item_kind:=lower(coalesce((public.erp_v764_definition_data(p_company_id,r.item_type,r.item_id))->>'itemType',
                                (public.erp_v764_definition_data(p_company_id,r.item_type,r.item_id))->>'item_type','stock'));
      if item_kind='service' then
        raise exception 'purchase_service_not_inventory_item:%',r.item_id;
      end if;
      cost_currency:=upper(coalesce(ac->>'currency',c));
      perform public.erp_phase2_account_guard(p_company_id,ac->>'assetAccountId','asset',cost_currency);
      perform public.erp_phase2_account_guard(p_company_id,ac->>'costExpenseAccountId','expense',cost_currency);
      -- Purchase invoicing intentionally does not require a revenue account.
    end loop;
  end if;

  return jsonb_build_object('ok',true,'invoiceId',p_invoice_id,'orderId',d.parent_id,
    'module',p_module,'currency',c,'partnerAccountId',partner_account);
end; $$;

create or replace function public.erp_v767_approve_invoice_safe(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare pre jsonb; result jsonb;
begin
  pre:=public.erp_v767_invoice_policy_preflight(p_company_id,p_invoice_id,p_module);
  result:=public.erp_v762_approve_workflow_invoice(p_company_id,p_invoice_id,p_module);
  return coalesce(result,'{}'::jsonb)||jsonb_build_object('ok',true,'preflight',pre,'version','v767');
exception when others then
  return jsonb_build_object(
    'ok',false,'code',sqlstate,'error',sqlerrm,
    'details',jsonb_build_object('module',p_module,'invoiceId',p_invoice_id)::text,
    'hint','Invoice approval failed. Verify the partner account for the invoice currency and the item inventory/cost/revenue bindings.',
    'version','v767'
  );
end; $$;

create or replace function public.erp_v767_approve_sales_invoice_safe(p_company_id uuid,p_invoice_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  select public.erp_v767_approve_invoice_safe($1,$2,'sales')
$$;

create or replace function public.erp_v767_approve_purchase_invoice_safe(p_company_id uuid,p_invoice_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  select public.erp_v767_approve_invoice_safe($1,$2,'purchases')
$$;

revoke all on function public.erp_v767_assert_partner_ledgers(uuid,text,text) from public,anon;
revoke all on function public.erp_v767_invoice_policy_preflight(uuid,uuid,text) from public,anon;
revoke all on function public.erp_v767_approve_invoice_safe(uuid,uuid,text) from public,anon;
revoke all on function public.erp_v767_approve_sales_invoice_safe(uuid,uuid) from public,anon;
revoke all on function public.erp_v767_approve_purchase_invoice_safe(uuid,uuid) from public,anon;
grant execute on function public.erp_v767_assert_partner_ledgers(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_v767_invoice_policy_preflight(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_v767_approve_invoice_safe(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_v767_approve_sales_invoice_safe(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v767_approve_purchase_invoice_safe(uuid,uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
