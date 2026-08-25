-- Quality Line ERP 22.9.0 / V7.6.1
-- Operational invoice approval diagnostics and idempotent wrappers.
begin;

create or replace function public.erp_v761_approve_workflow_invoice(
  p_company_id uuid,
  p_invoice_id uuid,
  p_module text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  r jsonb;
begin
  if p_module not in ('sales','purchases') then
    raise exception using message='invalid_workflow_module', detail=p_module;
  end if;

  select * into d
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id
    and module=p_module and document_type='invoice' and not is_deleted
  for update;

  if not found then
    raise exception using message='workflow_invoice_not_found', detail=p_invoice_id::text;
  end if;

  if lower(coalesce(d.status,''))='approved' then
    return jsonb_build_object('ok',true,'alreadyApproved',true,'invoiceId',p_invoice_id);
  end if;

  begin
    r:=public.erp_v760_approve_workflow_invoice(p_company_id,p_invoice_id,p_module);
    return coalesce(r,'{}'::jsonb)||jsonb_build_object('ok',true,'invoiceId',p_invoice_id);
  exception when others then
    raise exception using
      message='workflow_invoice_approval_failed',
      detail=jsonb_build_object(
        'module',p_module,
        'invoiceId',p_invoice_id,
        'orderId',d.parent_id,
        'invoiceNumber',d.document_number,
        'invoiceStatus',d.status,
        'databaseMessage',sqlerrm,
        'databaseState',sqlstate
      )::text,
      hint='Refresh the order, verify the approved warehouse document and configured partner/item accounts, then retry.';
  end;
end;
$$;

create or replace function public.erp_approve_cloud_sales_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_v761_approve_workflow_invoice(p_company_id,p_invoice_id,'sales');
end;
$$;

create or replace function public.erp_approve_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_v761_approve_workflow_invoice(p_company_id,p_invoice_id,'purchases');
end;
$$;

revoke all on function public.erp_v761_approve_workflow_invoice(uuid,uuid,text) from public,anon;
grant execute on function public.erp_v761_approve_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
