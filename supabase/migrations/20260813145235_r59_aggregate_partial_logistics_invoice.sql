begin;

create or replace function public.erp_v736_active_logistics(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_type text; v_result jsonb;
begin
  v_type:=case when p_module='sales' then 'delivery' when p_module='purchases' then 'receipt' end;
  if v_type is null then raise exception 'invalid workflow module'; end if;
  with docs as (
    select d.* from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.parent_id=p_order_id and d.module=p_module
      and d.document_type=v_type and lower(coalesce(d.status,'')) in ('approved','posted','completed','confirmed')
      and not d.is_deleted and (d.payload ? 'inventoryPostedAt' or d.payload ? 'postedAt' or d.payload ? 'approvedAt')
  ), latest as (select * from docs order by updated_at desc,id desc limit 1), allocations as (
    select x."itemType",x."itemId",max(x."description") description,x."warehouseId",sum(x.quantity) quantity
    from docs d cross join lateral jsonb_to_recordset(coalesce(d.payload->'allocations','[]'::jsonb))
      x("itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by 1,2,4
  )
  select jsonb_build_object('id',l.id::text,'number',l.document_number,
    'documentIds',(select jsonb_agg(d.id order by d.effective_at,d.created_at,d.id) from docs d),
    'documentNumbers',(select jsonb_agg(d.document_number order by d.effective_at,d.created_at,d.id) from docs d),
    'allocations',(select jsonb_agg(jsonb_build_object('itemType',a."itemType",'itemId',a."itemId",
      'description',a.description,'warehouseId',a."warehouseId",'quantity',a.quantity) order by a."itemType",a."itemId",a."warehouseId") from allocations a),
    'effectiveAt',coalesce(l.effective_at,l.created_at),
    'warehouseIds',(select jsonb_agg(distinct a."warehouseId") from allocations a))
  into v_result from latest l;
  if v_result is null then raise exception 'approved_inventory_document_required'; end if;
  perform public.erp_validate_commercial_warehouse_allocations(p_company_id,p_order_id,p_module,v_result->'allocations',false);
  return v_result;
end $$;

create or replace function public.erp_r22_post_purchase_invoice_direct(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; v_invoice_total numeric;
  v_layer_total numeric; v_result jsonb; v_receipt_ids uuid[];
begin
  select * into d from public.erp_commercial_workflow_documents where company_id=p_company_id and id=p_invoice_id
    and module='purchases' and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  if d.status='approved' then return public.erp_r22_post_purchase_invoice_direct_pre_r54_valuation(p_company_id,p_invoice_id); end if;
  select array_agg(id order by effective_at,created_at,id) into v_receipt_ids
  from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=d.parent_id
    and module='purchases' and document_type='receipt' and status='approved' and not is_deleted;
  v_invoice_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  select coalesce(sum(original_quantity*unit_cost),0) into v_layer_total from public.erp_inventory_cost_layers
    where company_id=p_company_id and receipt_id=any(v_receipt_ids) and source_type='purchase_receipt';
  if coalesce(array_length(v_receipt_ids,1),0)=0 or v_layer_total<=0 then raise exception 'purchase_receipt_valuation_required'; end if;
  if abs(v_invoice_total-v_layer_total)>0.01 then raise exception 'purchase_invoice_operational_valuation_mismatch:%:%',v_invoice_total,v_layer_total; end if;
  v_result:=public.erp_r22_post_purchase_invoice_direct_pre_r54_valuation(p_company_id,p_invoice_id);
  update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
    'operationalValuationPreserved',true,'operationalValuationTotal',v_layer_total,
    'logisticsDocumentIds',to_jsonb(v_receipt_ids)) where company_id=p_company_id and id=p_invoice_id;
  update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
    'valuationPendingInvoice',false,'valuedByInvoiceId',p_invoice_id::text,'valuationAppliedAt',now()),updated_at=now()
    where company_id=p_company_id and id=any(v_receipt_ids);
  return v_result||jsonb_build_object('operationalValuationPreserved',true,'logisticsDocumentIds',to_jsonb(v_receipt_ids));
end $$;

revoke all on function public.erp_v736_active_logistics(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_v736_active_logistics(uuid,uuid,text) to service_role;
revoke all on function public.erp_r22_post_purchase_invoice_direct(uuid,uuid) from public,anon,authenticated;
grant execute on function public.erp_r22_post_purchase_invoice_direct(uuid,uuid) to service_role;

commit;
