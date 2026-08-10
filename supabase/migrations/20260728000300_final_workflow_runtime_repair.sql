begin;

-- Final runtime repair for the chart-of-accounts selector. The normalized
-- erp_accounts table has one canonical `name` column, not name_ar/name_en.
create or replace function public.erp_list_cloud_settlement_accounts(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'id',a.account_id,
    'code',a.code,
    'name',coalesce(nullif(a.name,''),a.code),
    'nameAr',coalesce(nullif(a.name,''),a.code),
    'nameEn',coalesce(nullif(a.name,''),a.code),
    'type',a.account_type,
    'currency',a.currency
  )
  from public.erp_accounts a
  where a.organization_id=p_company_id
    and a.is_active
    and public.erp_is_company_member(p_company_id)
  order by a.code,a.name;
$$;

-- Restore an edited commercial order using the batch payment engine. The old
-- implementation called the single-payment function directly, which rejects
-- the persisted `full` and `settlement` modes and caused saving an edited order
-- to fail after a full or settlement payment existed.
create or replace function public.erp_restore_commercial_order_links(
  p_company_id uuid,p_order_id uuid,p_module text,p_snapshot jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_logistics jsonb:=p_snapshot->'logistics';
  v_invoice jsonb:=p_snapshot->'invoice';
  v_payments jsonb:=coalesce(p_snapshot->'payments','[]'::jsonb);
  v_normalized_payments jsonb:='[]'::jsonb;
  v_payment jsonb;
  v_mode text;
  v_logistics_id uuid;
  v_invoice_id uuid;
  v_order_status text:=p_snapshot->>'orderStatus';
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;

  if v_order_status='approved' or v_logistics is not null or v_invoice is not null then
    if p_module='sales' then
      perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
    else
      perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
    end if;
  end if;

  if v_logistics is not null then
    if nullif(v_logistics->>'warehouseId','') is null then
      raise exception 'المستند المخزني السابق لا يحتوي على مخزن صالح';
    end if;
    if p_module='sales' then
      v_logistics_id:=public.erp_create_cloud_sales_delivery(
        p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes');
      if v_logistics->>'status'='approved' then
        perform public.erp_approve_cloud_sales_delivery(p_company_id,v_logistics_id);
      end if;
    else
      v_logistics_id:=public.erp_create_cloud_purchase_receipt(
        p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes');
      if v_logistics->>'status'='approved' then
        perform public.erp_approve_cloud_purchase_receipt(p_company_id,v_logistics_id);
      end if;
    end if;
  end if;

  if v_invoice is not null then
    if p_module='sales' then
      v_invoice_id:=public.erp_create_cloud_sales_workflow_invoice(p_company_id,p_order_id);
      if v_invoice->>'status'='approved' then
        perform public.erp_approve_cloud_sales_workflow_invoice(p_company_id,v_invoice_id);
      end if;
    else
      v_invoice_id:=public.erp_create_cloud_purchase_workflow_invoice(p_company_id,p_order_id);
      if v_invoice->>'status'='approved' then
        perform public.erp_approve_cloud_purchase_workflow_invoice(p_company_id,v_invoice_id);
      end if;
    end if;

    if jsonb_array_length(v_payments)>0 and v_invoice->>'status'<>'approved' then
      raise exception 'لا يمكن إعادة الدفعات إلى فاتورة غير مصدقة';
    end if;

    for v_payment in select value from jsonb_array_elements(v_payments) loop
      v_mode:=lower(btrim(coalesce(v_payment->>'settlementMode','partial')));
      v_mode:=case
        when v_mode in ('full','fullwithexchangedifference') then 'full'
        when v_mode in ('settlement','full_fx') and nullif(v_payment->>'settlementAccountId','') is not null then 'settlement'
        when v_mode in ('full_fx','fullwithexchangedifference') then 'full'
        else 'partial'
      end;
      v_normalized_payments:=v_normalized_payments||jsonb_build_array(
        (v_payment
          - 'paymentId' - 'paymentKey' - 'journalEntryId' - 'cashTransactionId'
          - 'previousRemainingAmount' - 'remainingAmount' - 'createdAt' - 'createdBy')
        ||jsonb_build_object('settlementMode',v_mode)
      );
    end loop;

    if jsonb_array_length(v_normalized_payments)>0 then
      perform public.erp_apply_cloud_workflow_invoice_payment_batch(
        p_company_id,v_invoice_id,p_module,v_normalized_payments
      );
    end if;
  end if;

  return jsonb_build_object(
    'orderId',p_order_id,
    'logisticsId',v_logistics_id,
    'invoiceId',v_invoice_id
  );
end;
$$;

-- Keep purchase selection permissive for active, defined master data. A car
-- that is already linked to another active purchase order remains excluded.
create or replace function public.erp_cloud_purchase_order_catalog(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'itemType','car','id',c.id,
    'description',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),
    'baseCost',coalesce(
      public.erp_try_numeric(c.data->>'purchasePrice',null),
      public.erp_try_numeric(c.data->>'costPrice',null),
      public.erp_try_numeric(c.data->>'unitCost',0)
    ),
    'imagePath',coalesce(c.data->>'imagePath',c.data->>'image'),
    'details',c.data||jsonb_build_object(
      'id',c.id,
      'plateNumber',coalesce(c.data->>'plateNumber',c.data->>'plate'),
      'chassis',coalesce(c.data->>'chassis',c.data->>'chassisNumber',c.data->>'vin'),
      'purchasePrice',coalesce(c.data->>'purchasePrice',c.data->>'costPrice',c.data->>'unitCost'),
      'salePrice',c.data->>'salePrice'
    )
  )
  from public.erp_cars c
  where c.company_id=p_company_id and not c.is_deleted
    and public.erp_is_company_member(p_company_id)
    and lower(btrim(coalesce(c.data->>'status','known'))) in (
      'known','identified','defined','registered','purchase_pending','pending_purchase',
      'available','new','draft','معرفة','معرّفة','مُعرفة','قيد الشراء','قيد شراء',
      'متوفرة','متوفر','متاحة','جديدة','مسودة'
    )
    and not exists(
      select 1
      from public.erp_purchase_order_items_cloud x
      join public.erp_purchase_orders_cloud o
        on o.company_id=x.company_id and o.id=x.order_id and not o.is_deleted
      where x.company_id=c.company_id and not x.is_deleted
        and x.item_type='car' and x.item_id=c.id
        and o.status in ('draft','approved')
    )
  union all
  select jsonb_build_object(
    'itemType','product','id',i.id,
    'description',coalesce(i.data->>'name',i.data->>'code',i.id),
    'baseCost',coalesce(
      public.erp_try_numeric(i.data->>'unitCost',null),
      public.erp_try_numeric(i.data->>'costPrice',null),
      public.erp_try_numeric(i.data->>'purchasePrice',0)
    ),
    'imagePath',coalesce(i.data->>'imagePath',i.data->>'image'),
    'details',i.data||jsonb_build_object(
      'id',i.id,
      'code',coalesce(i.data->>'code',i.data->>'sku',i.id),
      'unitCost',coalesce(i.data->>'unitCost',i.data->>'costPrice',i.data->>'purchasePrice'),
      'salePrice',coalesce(i.data->>'salePrice',i.data->>'unitPrice')
    )
  )
  from public.erp_inventory i
  where i.company_id=p_company_id and not i.is_deleted
    and public.erp_try_boolean(i.data->>'isActive',true)
    and public.erp_is_company_member(p_company_id);
$$;

grant execute on function public.erp_list_cloud_settlement_accounts(uuid) to authenticated;
grant execute on function public.erp_restore_commercial_order_links(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.erp_cloud_purchase_order_catalog(uuid) to authenticated;

commit;
