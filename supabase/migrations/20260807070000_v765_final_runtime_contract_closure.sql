-- Quality Line ERP V7.6.5 / 22.9.6 final pre-runtime contract closure
begin;

create or replace function public.erp_v765_invoice_policy_preflight(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; partner_id text; r record; c text;
begin
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  c:=upper(coalesce(d.payload->>'currency',''));
  if c not in ('USD','IQD') then raise exception 'workflow_invoice_currency_invalid:%',c; end if;
  if p_module='sales' then
    select customer_id into partner_id from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=d.parent_id and not is_deleted;
    perform public.erp_v764_assert_partner_dual_ledgers(p_company_id,partner_id,'customer');
    for r in select item_type,item_id from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted loop
      if public.erp_v764_definition_currency(p_company_id,r.item_type,r.item_id)<>c then
        raise exception 'sales_item_currency_mismatch:%',r.item_id;
      end if;
      perform public.erp_v764_definition_accounts(p_company_id,r.item_type,r.item_id);
    end loop;
  elsif p_module='purchases' then
    select supplier_id into partner_id from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=d.parent_id and not is_deleted;
    perform public.erp_v764_assert_partner_dual_ledgers(p_company_id,partner_id,'supplier');
    for r in select item_type,item_id from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted loop
      if public.erp_v764_definition_currency(p_company_id,r.item_type,r.item_id)<>c then
        raise exception 'purchase_item_currency_mismatch:%',r.item_id;
      end if;
      perform public.erp_v764_definition_accounts(p_company_id,r.item_type,r.item_id);
    end loop;
  else raise exception 'invalid_workflow_module:%',p_module;
  end if;
  return jsonb_build_object('ok',true,'invoiceId',p_invoice_id,'orderId',d.parent_id,'currency',c);
end; $$;

create or replace function public.erp_v765_approve_invoice_safe(p_company_id uuid,p_invoice_id uuid,p_module text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pre jsonb; result jsonb;
begin
  pre:=public.erp_v765_invoice_policy_preflight(p_company_id,p_invoice_id,p_module);
  result:=public.erp_v762_approve_workflow_invoice(p_company_id,p_invoice_id,p_module);
  return coalesce(result,'{}'::jsonb)||jsonb_build_object('ok',true,'preflight',pre);
exception when others then
  return jsonb_build_object('ok',false,'code',sqlstate,'error',sqlerrm,
    'details',jsonb_build_object('module',p_module,'invoiceId',p_invoice_id)::text,
    'hint','Invoice approval failed policy/accounting preflight. Correct the reported account/currency binding and retry.');
end; $$;

create or replace function public.erp_v765_approve_sales_invoice_safe(p_company_id uuid,p_invoice_id uuid)
returns jsonb language sql security definer set search_path=public as $$select public.erp_v765_approve_invoice_safe($1,$2,'sales')$$;
create or replace function public.erp_v765_approve_purchase_invoice_safe(p_company_id uuid,p_invoice_id uuid)
returns jsonb language sql security definer set search_path=public as $$select public.erp_v765_approve_invoice_safe($1,$2,'purchases')$$;

revoke all on function public.erp_v765_invoice_policy_preflight(uuid,uuid,text) from public,anon;
revoke all on function public.erp_v765_approve_invoice_safe(uuid,uuid,text) from public,anon;
revoke all on function public.erp_v765_approve_sales_invoice_safe(uuid,uuid) from public,anon;
revoke all on function public.erp_v765_approve_purchase_invoice_safe(uuid,uuid) from public,anon;
grant execute on function public.erp_v765_invoice_policy_preflight(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_v765_approve_invoice_safe(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_v765_approve_sales_invoice_safe(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v765_approve_purchase_invoice_safe(uuid,uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
