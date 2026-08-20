-- Quality Line ERP / KAJ ERP R89
-- Phase 11 completion closure.
-- Forward-only fixes for secure operational detail reads, cash-flow cashbox
-- scoping, recurring vehicle maintenance schedules, and exact notification
-- navigation metadata. Historical migrations are intentionally untouched.
begin;

-- ---------------------------------------------------------------------------
-- 1. Secure commercial Details & Items boundary.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r89_commercial_detail_field_for_key(
  p_module text,p_key text,p_kind text
) returns text
language plpgsql immutable as $$
declare
  v_module text:=lower(btrim(coalesce(p_module,'')));
  v_key text:=btrim(coalesce(p_key,''));
  v_kind text:=lower(btrim(coalesce(p_kind,'')));
begin
  if v_kind='order' then
    return case v_key
      when 'partnerName' then case when v_module='purchases' then 'supplierName' else 'customerName' end
      when 'createdBy' then 'createdBy'
      when 'createdByName' then 'createdBy'
      when 'operationalDateTime' then 'operationalDate'
      when 'orderDate' then 'operationalDate'
      else public.erp_r9_result_field_for_key(v_module,v_key)
    end;
  elsif v_kind in ('item','reconciliation') then
    return case
      when v_key in ('itemId','productId','productName','itemName','name','description','itemCode','code','itemType','lineType','carId','carName') then 'items'
      when v_key in ('warehouseId','warehouseName') then 'itemWarehouse'
      when v_key in ('quantity','orderedQuantity','requestedQuantity','operationalQuantity','warehouseQuantity','receivedQuantity','issuedQuantity','invoicedQuantity','remainingQuantity') then 'itemQuantity'
      when v_key in ('unitCost','purchasePrice','cost','actualUnitCost','actualCost') and v_module='purchases' then 'itemCost'
      when v_key in ('unitCost','purchasePrice','cost','actualUnitCost','actualCost') and v_module='sales' then null
      when v_key in ('unitPrice','price','sellingPrice','salePrice','lineTotal','lineAmount') then case when v_module='purchases' then 'itemCost' else 'itemPrice' end
      when v_key in ('currency','currencyCode') then 'currencyCode'
      when v_key in ('discount','discountAmount') then 'discount'
      when v_key in ('subtotal','total','totalAmount') then 'total'
      when v_key in ('status','workflowStage') then 'status'
      else null
    end;
  elsif v_kind='logistics' then
    return case
      when v_key in ('receiptNumber','deliveryNumber','documentNumber','referenceDocumentNumber','status','approvalAction','sourceName','destinationName','effectiveAt','createdAt','updatedAt','approvedAt','performedBy','approvedBy')
        then case when v_module='purchases' then 'receipt' else 'delivery' end
      when v_key in ('warehouseId','warehouseName') then 'itemWarehouse'
      when v_key in ('quantity','orderedQuantity','receivedQuantity','issuedQuantity','remainingQuantity') then 'itemQuantity'
      when v_key in ('currency','currencyCode') then 'currencyCode'
      when v_key in ('createdBy','createdByName') then 'createdBy'
      else null
    end;
  elsif v_kind='invoice' then
    return case
      when v_key in ('invoiceId','invoiceNumber','documentNumber','status','invoiceStatus','approvedAt','approvedBy') then 'invoice'
      when v_key in ('createdAt','updatedAt','effectiveAt','invoiceDate') then 'invoice'
      when v_key in ('createdBy','createdByName','postedBy','postedByName') then 'createdBy'
      when v_key in ('currency','currencyCode') then 'currencyCode'
      when v_key in ('subtotal','total','totalAmount','lineTotal','tax','taxAmount') then 'total'
      when v_key in ('discount','discountAmount') then 'discount'
      else null
    end;
  elsif v_kind='payment' then
    return case
      when v_key in ('paymentId','cashTransactionId','voucherNumber','paymentReference','status','cashAccountId','cashAccountName','cashAccountCurrency','transactionDate','paymentDate','createdAt','relatedDocument','invoiceId','invoiceNumber') then 'payments'
      when v_key in ('amount','paidAmount','remainingAmount') then 'payments'
      when v_key in ('currency','paymentCurrency','cashAccountCurrency') then 'currencyCode'
      when v_key in ('exchangeRate','fxRate','baseAmount','foreignAmount') then 'exchangeRate'
      when v_key in ('createdBy','createdByName','userName') then 'createdBy'
      else null
    end;
  elsif v_kind='movement' then
    return case
      when v_key in ('movementNumber','movementType','movementDate','referenceType','referenceId','referenceDocumentNumber','sourceName','destinationName','performedBy') then case when v_module='purchases' then 'receipt' else 'delivery' end
      when v_key in ('productId','productName','itemId','itemName','description') then 'items'
      when v_key in ('warehouseId','warehouseName','sourceWarehouseId','destinationWarehouseId') then 'itemWarehouse'
      when v_key in ('quantity','receivedQuantity','issuedQuantity') then 'itemQuantity'
      else null
    end;
  elsif v_kind='audit' then
    return case
      when v_key in ('performedBy','performedByName','actorUser','createdBy','createdByName') then 'createdBy'
      when v_key in ('performedAt','createdAt','updatedAt') then 'updatedAt'
      when v_key in ('action','fromStatus','toStatus','status') then 'status'
      else null
    end;
  end if;
  return null;
end;
$$;

create or replace function public.erp_r89_filter_commercial_detail_row(
  p_company_id uuid,p_module text,p_payload jsonb,p_kind text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_field text;
begin
  if p_payload is null then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,btrim(p_module)||'.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    if v_item.key in ('rawData','raw_data','recordMeta','invoiceRawData','payload','invoicePayload','details','allocations','items','lines') then
      continue;
    end if;
    v_field:=public.erp_r89_commercial_detail_field_for_key(p_module,v_item.key,p_kind);
    if v_item.key='id'
       or (v_field is not null and public.erp_cloud_user_can_view_field(
         p_company_id,p_module,v_field,null
       )) then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r89_filter_commercial_line_array(
  p_company_id uuid,p_module text,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='[]'::jsonb;
  v_row jsonb;
begin
  if jsonb_typeof(p_payload)<>'array' then return '[]'::jsonb; end if;
  for v_row in select value from jsonb_array_elements(p_payload) loop
    v_result:=v_result||jsonb_build_array(
      public.erp_r89_filter_commercial_detail_row(
        p_company_id,p_module,v_row,'item'
      )
    );
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r89_filter_commercial_detail_array(
  p_company_id uuid,p_module text,p_payload jsonb,p_kind text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='[]'::jsonb;
  v_row jsonb;
begin
  if jsonb_typeof(p_payload)<>'array' then return '[]'::jsonb; end if;
  for v_row in select value from jsonb_array_elements(p_payload) loop
    v_result:=v_result||jsonb_build_array(
      public.erp_r89_filter_commercial_detail_row(
        p_company_id,p_module,v_row,p_kind
      )
    );
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r89_filter_commercial_document_array(
  p_company_id uuid,p_module text,p_payload jsonb,p_kind text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='[]'::jsonb;
  v_row jsonb;
  v_safe jsonb;
  v_lines jsonb;
  v_line_key text;
begin
  if jsonb_typeof(p_payload)<>'array' then return '[]'::jsonb; end if;
  for v_row in select value from jsonb_array_elements(p_payload) loop
    v_safe:=public.erp_r89_filter_commercial_detail_row(
      p_company_id,p_module,v_row,p_kind
    );
    v_lines:=case
      when jsonb_typeof(v_row->'allocations')='array' then v_row->'allocations'
      when jsonb_typeof(v_row->'items')='array' then v_row->'items'
      when jsonb_typeof(v_row->'lines')='array' then v_row->'lines'
      when jsonb_typeof(v_row->'payload'->'allocations')='array' then v_row->'payload'->'allocations'
      when jsonb_typeof(v_row->'payload'->'items')='array' then v_row->'payload'->'items'
      when jsonb_typeof(v_row->'payload'->'lines')='array' then v_row->'payload'->'lines'
      when jsonb_typeof(v_row->'invoicePayload'->'allocations')='array' then v_row->'invoicePayload'->'allocations'
      when jsonb_typeof(v_row->'invoicePayload'->'items')='array' then v_row->'invoicePayload'->'items'
      when jsonb_typeof(v_row->'invoicePayload'->'lines')='array' then v_row->'invoicePayload'->'lines'
      else '[]'::jsonb end;
    v_line_key:=case when lower(p_kind)='logistics' then 'allocations' else 'items' end;
    if jsonb_array_length(v_lines)>0
       and public.erp_cloud_user_can_view_field(p_company_id,p_module,'items',null) then
      v_safe:=v_safe||jsonb_build_object(
        v_line_key,
        public.erp_r89_filter_commercial_line_array(p_company_id,p_module,v_lines)
      );
    end if;
    v_result:=v_result||jsonb_build_array(v_safe);
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r89_filter_commercial_journal_array(
  p_company_id uuid,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='[]'::jsonb;
  v_row jsonb;
  v_safe jsonb;
  v_lines jsonb:='[]'::jsonb;
  v_line jsonb;
begin
  if jsonb_typeof(p_payload)<>'array' then return '[]'::jsonb; end if;
  for v_row in select value from jsonb_array_elements(p_payload) loop
    v_safe:=public.erp_r9_filter_result_json(
      p_company_id,'accounting',v_row-'rawData'-'recordMeta'-'lines',null
    );
    if jsonb_typeof(v_row->'lines')='array' then
      v_lines:='[]'::jsonb;
      for v_line in select value from jsonb_array_elements(v_row->'lines') loop
        v_lines:=v_lines||jsonb_build_array(
          public.erp_r9_filter_result_json(p_company_id,'accounting',v_line,null)
        );
      end loop;
      if jsonb_array_length(v_lines)>0 then
        v_safe:=v_safe||jsonb_build_object('lines',v_lines);
      end if;
    end if;
    v_result:=v_result||jsonb_build_array(v_safe);
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r89_get_commercial_order_snapshot(
  p_company_id uuid,p_order_id uuid,p_purchase boolean
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_module text:=case when p_purchase then 'purchases' else 'sales' end;
  v_creator uuid;
  v_details jsonb;
  v_order jsonb;
  v_opportunity jsonb:='{}'::jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,v_module||'.view') then
    raise exception 'permission_denied:%.view',v_module using errcode='42501';
  end if;

  if p_purchase then
    select created_by into v_creator
    from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  else
    select created_by into v_creator
    from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  end if;
  if not found or not public.erp_r84_record_visible(
    p_company_id,v_module,v_creator,null
  ) then
    raise exception 'commercial_order_not_found' using errcode='P0002';
  end if;

  v_details:=public.erp_r62_get_commercial_order_snapshot(
    p_company_id,p_order_id,p_purchase
  );
  if not public.erp_cloud_user_has_permission(p_company_id,v_module||'.fields.restrict') then
    return v_details;
  end if;

  v_order:=public.erp_r89_filter_commercial_detail_row(
    p_company_id,v_module,coalesce(v_details->'order','{}'::jsonb),'order'
  );

  if not p_purchase
     and public.erp_cloud_user_can_view_field(p_company_id,'sales','opportunityId',null)
     and public.erp_cloud_user_has_permission(p_company_id,'customer_service.view') then
    v_opportunity:=public.erp_r9_filter_result_json(
      p_company_id,'opportunities',coalesce(v_details->'opportunity','{}'::jsonb),null
    );
  end if;

  return jsonb_build_object(
    'order',v_order,
    'items',public.erp_r89_filter_commercial_detail_array(
      p_company_id,v_module,coalesce(v_details->'items','[]'::jsonb),'item'
    ),
    'logistics',case
      when public.erp_cloud_user_can_view_field(
        p_company_id,v_module,case when p_purchase then 'receipt' else 'delivery' end,null
      ) then public.erp_r89_filter_commercial_document_array(
        p_company_id,v_module,coalesce(v_details->'logistics','[]'::jsonb),'logistics'
      ) else '[]'::jsonb end,
    'invoices',case
      when public.erp_cloud_user_can_view_field(p_company_id,v_module,'invoice',null)
      then public.erp_r89_filter_commercial_document_array(
        p_company_id,v_module,coalesce(v_details->'invoices','[]'::jsonb),'invoice'
      ) else '[]'::jsonb end,
    'payments',case
      when public.erp_cloud_user_can_view_field(p_company_id,v_module,'payments',null)
      then public.erp_r89_filter_commercial_detail_array(
        p_company_id,v_module,coalesce(v_details->'payments','[]'::jsonb),'payment'
      ) else '[]'::jsonb end,
    'movements',case
      when public.erp_cloud_user_can_view_field(
        p_company_id,v_module,case when p_purchase then 'receipt' else 'delivery' end,null
      ) then public.erp_r89_filter_commercial_detail_array(
        p_company_id,v_module,coalesce(v_details->'movements','[]'::jsonb),'movement'
      ) else '[]'::jsonb end,
    'journalEntries',case
      when public.erp_cloud_user_can_view_field(p_company_id,v_module,'accounting',null)
      then public.erp_r89_filter_commercial_journal_array(
        p_company_id,coalesce(v_details->'journalEntries','[]'::jsonb)
      ) else '[]'::jsonb end,
    'auditTrail',public.erp_r89_filter_commercial_detail_array(
      p_company_id,v_module,coalesce(v_details->'auditTrail','[]'::jsonb),'audit'
    ),
    'reconciliation',public.erp_r89_filter_commercial_detail_array(
      p_company_id,v_module,coalesce(v_details->'reconciliation','[]'::jsonb),'reconciliation'
    ),
    'opportunity',v_opportunity
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Maintenance cost/material issue read boundaries.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r89_filter_maintenance_nested_array(
  p_company_id uuid,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='[]'::jsonb;
  v_row jsonb;
  v_safe jsonb;
  v_material boolean;
begin
  if jsonb_typeof(p_payload)<>'array' then return '[]'::jsonb; end if;
  v_material:=public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','materialCost',null
  ) or public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','partsCost',null
  );
  for v_row in select value from jsonb_array_elements(p_payload) loop
    v_safe:=public.erp_r9_filter_result_json(
      p_company_id,'maintenance',
      case when v_material then v_row else
        v_row-'unitCost'-'actualUnitCost'-'actualCost'-'cost'-'totalCost'-'requestedCost'-'issuedCost'
      end,
      null
    );
    if public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance','items',null
    ) and v_row ? 'lineId' then
      v_safe:=v_safe||jsonb_build_object('lineId',v_row->'lineId');
    end if;
    if public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance','itemQuantity',null
    ) then
      v_safe:=v_safe||(
        select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
        from jsonb_each(v_row)
        where key in (
          'requestedQuantity','issuedQuantity','remainingQuantity',
          'invoicedQuantity','approvedQuantity'
        )
      );
    end if;
    if public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance','stockIssue',null
    ) then
      v_safe:=v_safe||(
        select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
        from jsonb_each(v_row)
        where key in (
          'issueId','issueNumber','eventId','eventType','status',
          'effectiveAt','createdAt','approvedAt','performedBy','approvedBy'
        )
      );
    end if;
    if v_material then
      v_safe:=v_safe||(
        select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
        from jsonb_each(v_row)
        where key in ('unitCost','actualUnitCost','actualCost','cost','totalCost','requestedCost','issuedCost')
      );
    end if;
    v_result:=v_result||jsonb_build_array(v_safe);
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r89_filter_maintenance_cost_payload(
  p_company_id uuid,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_field text;
begin
  if p_payload is null then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    if v_item.key in ('lines','warehouses','events','issueEvents') then
      v_field:=case v_item.key
        when 'lines' then 'items'
        when 'warehouses' then 'stockIssue'
        else 'stockIssue' end;
      if public.erp_cloud_user_can_view_field(p_company_id,'maintenance',v_field,null) then
        v_result:=v_result||jsonb_build_object(
          v_item.key,public.erp_r89_filter_maintenance_nested_array(
            p_company_id,v_item.value
          )
        );
      end if;
      continue;
    end if;
    v_field:=case v_item.key
      when 'currency' then 'currencyCode'
      when 'workflowStage' then 'workflowStage'
      when 'hasApprovedInvoice' then 'invoice'
      when 'requestedCostAvailable' then 'partsCost'
      when 'requestedMaterialsCost' then 'partsCost'
      when 'requestedMaterialsCostByCurrency' then 'partsCost'
      when 'issuedMaterialsActualCost' then 'materialCost'
      when 'issuedMaterialsActualCostByCurrency' then 'materialCost'
      when 'materialDiscrepancy' then 'materialCost'
      when 'crossCurrencyMaterials' then 'materialCost'
      when 'issuedNotInvoicedCost' then 'materialCost'
      when 'laborCost' then 'laborCost'
      when 'additionalServicesCost' then 'laborCost'
      when 'laborInvoiced' then 'laborCost'
      when 'servicesInvoiced' then 'laborCost'
      when 'laborDiscrepancy' then 'laborCost'
      when 'totalOperationalCost' then 'totalCost'
      when 'materialsInvoiced' then 'invoice'
      when 'totalInvoiced' then 'invoice'
      when 'invoicedNotIssuedValue' then 'invoice'
      when 'discount' then 'invoice'
      when 'tax' then 'invoice'
      when 'paid' then 'payments'
      when 'outstanding' then 'payments'
      else public.erp_r9_result_field_for_key('maintenance',v_item.key)
    end;
    if v_field is not null and public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance',v_field,null
    ) then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r89_maintenance_cost_reconciliation(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_payload jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_maintenance_orders m
    where m.company_id=p_company_id and m.id=p_order_id and not m.is_deleted
      and public.erp_r84_record_visible(p_company_id,'maintenance',m.created_by,null)
  ) then raise exception 'maintenance_order_not_found' using errcode='P0002'; end if;
  v_payload:=public.erp_r57_maintenance_cost_reconciliation(p_company_id,p_order_id);
  return public.erp_r89_filter_maintenance_cost_payload(p_company_id,v_payload);
end;
$$;

create or replace function public.erp_r89_maintenance_material_issue_state(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_payload jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_maintenance_orders m
    where m.company_id=p_company_id and m.id=p_order_id and not m.is_deleted
      and public.erp_r84_record_visible(p_company_id,'maintenance',m.created_by,null)
  ) then raise exception 'maintenance_order_not_found' using errcode='P0002'; end if;
  v_payload:=public.erp_r57_maintenance_material_issue_state(p_company_id,p_order_id);
  return public.erp_r89_filter_maintenance_cost_payload(p_company_id,v_payload);
end;
$$;

create or replace function public.erp_r89_get_maintenance_order_snapshot(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb;
  v_reconciliation jsonb;
  v_issue jsonb;
begin
  v_base:=public.erp_r64_get_maintenance_order_snapshot(p_company_id,p_order_id);
  v_reconciliation:=public.erp_r89_maintenance_cost_reconciliation(p_company_id,p_order_id);
  v_issue:=public.erp_r89_maintenance_material_issue_state(p_company_id,p_order_id);
  return jsonb_set(
    jsonb_set(v_base,'{reconciliation}',v_reconciliation,true),
    '{issueState}',v_issue,true
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Cash Flow Statement: explicit cashbox scope + field-filtered rows.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r89_filter_cash_flow_row(
  p_company_id uuid,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_allowed boolean;
begin
  if p_payload is null then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.fields.restrict')
     and not public.erp_cloud_user_has_permission(p_company_id,'reports.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    v_allowed:=case v_item.key
      when 'cashIn' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','cashFlow',null)
        and public.erp_cloud_user_can_view_field(p_company_id,'reports','cashIn',null)
      when 'cashOut' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','cashFlow',null)
        and public.erp_cloud_user_can_view_field(p_company_id,'reports','cashOut',null)
      when 'netCashFlow' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','cashFlow',null)
        and public.erp_cloud_user_can_view_field(p_company_id,'reports','netCashFlow',null)
      when 'runningBalance' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','balances',null)
      when 'currency' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','currency',null)
      when 'entryDate' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','entryDate',null)
      when 'entryNumber' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','entryNumber',null)
      when 'accountCode' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountCode',null)
      when 'rootAccountCode' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountCode',null)
      when 'accountName' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountName',null)
      when 'rootAccountName' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountName',null)
      when 'hierarchyPath' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountName',null)
      when 'accountType' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountType',null)
      when 'parentAccountId' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','parentAccount',null)
      when 'description' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','description',null)
      when 'partyName' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','reference',null)
      when 'paymentMethod' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','reference',null)
      when 'referenceType' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','reference',null)
      when 'referenceId' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','reference',null)
      when 'debit' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','debit',null)
      when 'credit' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','credit',null)
      when 'cashAccountId' then public.erp_cloud_user_can_view_field(p_company_id,'cashbox','name',null)
      when 'flowDirection' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','cashFlow',null)
      when 'flowSection' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','cashFlow',null)
      when 'hierarchyDepth' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountName',null)
      when 'accountId' then public.erp_cloud_user_can_view_field(p_company_id,'accounting','accountName',null)
      else false end;
    if v_allowed then v_result:=v_result||jsonb_build_object(v_item.key,v_item.value); end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r89_list_cashboxes_for_cash_flow(
  p_company_id uuid
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',c.id,
    'name',case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','name',null)
      then coalesce(c.data->>'name',c.id) else c.id end,
    'currency',case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','currency',null)
      then upper(coalesce(nullif(c.data->>'currency',''),'IQD')) else '' end
  )
  from public.erp_cash_accounts c
  where c.company_id=p_company_id and not c.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_cloud_user_can_view_field(
      p_company_id,'accounting','cashFlow','accounting.view'
    )
    and public.erp_cloud_user_can_view_field(
      p_company_id,'reports','cashboxFilter',null
    )
  order by lower(coalesce(c.data->>'name',c.id));
$$;

create or replace function public.erp_r89_cloud_cash_flow_hierarchy(
  p_company_id uuid,p_currency text default 'ALL',p_cash_account_id text default null,
  p_branch_id text default null,p_cost_center_id text default null,
  p_from_date timestamptz default null,p_to_date timestamptz default null
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r89_filter_cash_flow_row(p_company_id,x)
  from public.erp_r9_cloud_cash_flow_hierarchy(
    p_company_id,p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
  ) x
  where nullif(btrim(coalesce(p_cash_account_id,'')),'') is null
     or x->>'cashAccountId'=p_cash_account_id;
$$;

-- ---------------------------------------------------------------------------
-- 4. Vehicle schedule recurrence is operational, not display-only.
-- ---------------------------------------------------------------------------
alter table public.erp_vehicle_maintenance_schedules
  add column if not exists recurrence_series_id uuid,
  add column if not exists recurrence_sequence integer not null default 0;
update public.erp_vehicle_maintenance_schedules
set recurrence_series_id=id
where recurrence_series_id is null;
create unique index if not exists erp_vehicle_maintenance_schedule_series_idx
  on public.erp_vehicle_maintenance_schedules(
    company_id,recurrence_series_id,recurrence_sequence
  ) where not is_deleted and recurrence_series_id is not null;

create or replace function public.erp_r89_spawn_next_maintenance_schedule()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_due timestamptz;
  v_series uuid;
begin
  if new.is_deleted or new.recurrence='none' then return new; end if;
  -- A schedule occurrence is consumed either when the user explicitly marks it
  -- completed or when it is converted into a real maintenance order. In both
  -- cases the next recurring occurrence must exist independently.
  if old.status is not distinct from new.status
     or new.status not in ('completed','converted') then return new; end if;
  v_due:=case new.recurrence
    when 'daily' then new.due_at+interval '1 day'
    when 'weekly' then new.due_at+interval '1 week'
    when 'monthly' then new.due_at+interval '1 month'
    when 'yearly' then new.due_at+interval '1 year'
    else null end;
  if v_due is null then return new; end if;
  v_series:=coalesce(new.recurrence_series_id,new.id);
  insert into public.erp_vehicle_maintenance_schedules(
    id,company_id,car_id,title,description,due_at,recurrence,
    assigned_user_id,created_by,reminder_minutes,status,
    linked_maintenance_order_id,last_reminded_at,is_deleted,
    created_at,updated_at,recurrence_series_id,recurrence_sequence
  ) values(
    gen_random_uuid(),new.company_id,new.car_id,new.title,new.description,v_due,new.recurrence,
    new.assigned_user_id,coalesce(auth.uid(),new.created_by),new.reminder_minutes,'scheduled',
    null,null,false,now(),now(),v_series,new.recurrence_sequence+1
  ) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists erp_r89_spawn_next_maintenance_schedule
  on public.erp_vehicle_maintenance_schedules;
create trigger erp_r89_spawn_next_maintenance_schedule
after update of status on public.erp_vehicle_maintenance_schedules
for each row execute function public.erp_r89_spawn_next_maintenance_schedule();

-- Backfill a single next occurrence for recurring schedules that were already
-- completed/converted between R88 and this forward-only migration. The unique
-- series/sequence index makes this idempotent.
insert into public.erp_vehicle_maintenance_schedules(
  id,company_id,car_id,title,description,due_at,recurrence,
  assigned_user_id,created_by,reminder_minutes,status,
  linked_maintenance_order_id,last_reminded_at,is_deleted,
  created_at,updated_at,recurrence_series_id,recurrence_sequence
)
select
  gen_random_uuid(),s.company_id,s.car_id,s.title,s.description,
  case s.recurrence
    when 'daily' then s.due_at+interval '1 day'
    when 'weekly' then s.due_at+interval '1 week'
    when 'monthly' then s.due_at+interval '1 month'
    when 'yearly' then s.due_at+interval '1 year'
  end,
  s.recurrence,s.assigned_user_id,s.created_by,s.reminder_minutes,'scheduled',
  null,null,false,now(),now(),coalesce(s.recurrence_series_id,s.id),
  s.recurrence_sequence+1
from public.erp_vehicle_maintenance_schedules s
where not s.is_deleted
  and s.recurrence in ('daily','weekly','monthly','yearly')
  and s.status in ('completed','converted')
on conflict do nothing;

-- Direct table DML is no longer an alternate path around the action/assignment
-- checks in the R88 RPCs. RLS remains enabled as defense in depth.
revoke all on table public.erp_vehicle_maintenance_schedules from public,anon,authenticated;
revoke all on table public.erp_maintenance_history_details from public,anon,authenticated;

-- Refresh the reminder materializer so every reminder has an exact vehicle
-- deep-link target. Recurring successors are independent rows and therefore
-- receive independent idempotent reminders.
create or replace function public.erp_r88_materialize_maintenance_schedule_reminders(
  p_company_id uuid,p_now timestamptz default now()
) returns integer
language plpgsql security definer set search_path=public as $$
declare r record; v_count integer:=0; v_event_key text; v_car_name text;
begin
  perform public.erp_active_company_context(p_company_id);
  for r in
    select s.*,coalesce(ap.full_name,'') assigned_name,
      coalesce(cp.full_name,'') creator_name
    from public.erp_vehicle_maintenance_schedules s
    left join public.profiles ap on ap.id=s.assigned_user_id
    left join public.profiles cp on cp.id=s.created_by
    where s.company_id=p_company_id and not s.is_deleted
      and s.status in ('scheduled','due')
      and s.due_at-(s.reminder_minutes||' minutes')::interval<=p_now
      and (s.last_reminded_at is null or s.last_reminded_at<s.updated_at)
  loop
    select coalesce(
      nullif(c.data->>'displayName',''),nullif(c.data->>'name',''),
      nullif(c.data->>'model',''),r.car_id
    ) into v_car_name
    from public.erp_cars c
    where c.company_id=p_company_id and c.id=r.car_id;
    v_event_key:='r89:maintenance_schedule:'||r.id::text||':'||r.updated_at::text;
    insert into public.erp_enterprise_notifications(company_id,id,data)
    values(p_company_id,gen_random_uuid(),jsonb_build_object(
      'eventKey',v_event_key,
      'eventType','maintenance_schedule_reminder',
      'event','maintenance_schedule_reminder','type','reminder',
      'module','maintenance','userId',r.assigned_user_id::text,
      'targetUserId',r.assigned_user_id,'targetUser',r.assigned_name,
      'actorUserId',r.created_by,'actorUser',r.creator_name,
      'referenceType','car','referenceId',r.car_id,
      'scheduleId',r.id::text,'documentReference',r.title,
      'carId',r.car_id,'carName',coalesce(v_car_name,r.car_id),
      'dueAt',r.due_at,'reminderMinutes',r.reminder_minutes,
      'recurrence',r.recurrence,'recurrenceSequence',r.recurrence_sequence,
      'deepLink','/inventory',
      'titleAr','تذكير صيانة: '||r.title,
      'titleEn','Maintenance reminder: '||r.title,
      'bodyAr','موعد صيانة '||coalesce(v_car_name,r.car_id)||' في '||r.due_at::text,
      'bodyEn','Maintenance for '||coalesce(v_car_name,r.car_id)||' is due at '||r.due_at::text,
      'createdAt',p_now
    )) on conflict do nothing;
    update public.erp_vehicle_maintenance_schedules
    set last_reminded_at=p_now,
        status=case when due_at<=p_now then 'due' else status end
    where company_id=p_company_id and id=r.id;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Privilege boundary and schema reload.
-- ---------------------------------------------------------------------------
revoke all on function public.erp_r89_commercial_detail_field_for_key(text,text,text) from public,anon;
revoke all on function public.erp_r89_filter_commercial_detail_row(uuid,text,jsonb,text) from public,anon;
revoke all on function public.erp_r89_filter_commercial_line_array(uuid,text,jsonb) from public,anon;
revoke all on function public.erp_r89_filter_commercial_detail_array(uuid,text,jsonb,text) from public,anon;
revoke all on function public.erp_r89_filter_commercial_document_array(uuid,text,jsonb,text) from public,anon;
revoke all on function public.erp_r89_filter_commercial_journal_array(uuid,jsonb) from public,anon;
revoke all on function public.erp_r89_get_commercial_order_snapshot(uuid,uuid,boolean) from public,anon;
revoke all on function public.erp_r89_filter_maintenance_nested_array(uuid,jsonb) from public,anon;
revoke all on function public.erp_r89_filter_maintenance_cost_payload(uuid,jsonb) from public,anon;
revoke all on function public.erp_r89_maintenance_cost_reconciliation(uuid,uuid) from public,anon;
revoke all on function public.erp_r89_maintenance_material_issue_state(uuid,uuid) from public,anon;
revoke all on function public.erp_r89_get_maintenance_order_snapshot(uuid,uuid) from public,anon;
revoke all on function public.erp_r89_filter_cash_flow_row(uuid,jsonb) from public,anon;
revoke all on function public.erp_r89_list_cashboxes_for_cash_flow(uuid) from public,anon;
revoke all on function public.erp_r89_cloud_cash_flow_hierarchy(uuid,text,text,text,text,timestamptz,timestamptz) from public,anon;
revoke all on function public.erp_r89_spawn_next_maintenance_schedule() from public,anon,authenticated;

grant execute on function public.erp_r89_get_commercial_order_snapshot(uuid,uuid,boolean) to authenticated,service_role;
grant execute on function public.erp_r89_maintenance_cost_reconciliation(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r89_maintenance_material_issue_state(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r89_get_maintenance_order_snapshot(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r89_list_cashboxes_for_cash_flow(uuid) to authenticated,service_role;
grant execute on function public.erp_r89_cloud_cash_flow_hierarchy(uuid,text,text,text,text,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r88_materialize_maintenance_schedule_reminders(uuid,timestamptz) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
