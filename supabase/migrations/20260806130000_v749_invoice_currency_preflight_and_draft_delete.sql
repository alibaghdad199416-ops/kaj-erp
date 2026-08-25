-- Quality Line ERP 18.9.19 / V7.4.9
-- Repairs invoice creation/approval when the order currency differs from an
-- item's inventory-cost currency, and keeps draft invoices removable so they
-- never block logistics/order reversal.
begin;

create or replace function public.erp_v749_prepare_order_invoice_accounts(
  p_company_id uuid,
  p_module text,
  p_order_id uuid,
  p_currency text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_currency text:=upper(nullif(btrim(coalesce(p_currency,'')),''));
  v_partner_id text;
  v_partner_type text;
  r record;
  v_accounts jsonb;
begin
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module';
  end if;
  if v_currency not in ('IQD','USD') then
    raise exception 'invalid_invoice_currency:%',coalesce(v_currency,'');
  end if;

  if p_module='sales' then
    select customer_id into v_partner_id
    from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    v_partner_type:='customer';
    if not found then raise exception 'sales_order_not_found'; end if;

    -- Ensure the partner has the receivable account matching the order currency.
    perform public.erp_workflow_partner_account(
      p_company_id,v_partner_type,v_partner_id,v_currency
    );

    for r in
      select item_type,item_id
      from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted
      order by id
    loop
      -- Revenue follows the invoice currency while inventory/cost accounts keep
      -- the item's own configured cost currency. Different currencies are valid.
      v_accounts:=public.erp_v736_item_accounting(
        p_company_id,r.item_type,r.item_id,v_currency
      );
    end loop;
  else
    select supplier_id into v_partner_id
    from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    v_partner_type:='supplier';
    if not found then raise exception 'purchase_order_not_found'; end if;

    perform public.erp_workflow_partner_account(
      p_company_id,v_partner_type,v_partner_id,v_currency
    );

    for r in
      select item_type,item_id
      from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted
      order by id
    loop
      -- Purchase inventory valuation remains in the item's configured cost
      -- currency and is converted from the order currency only at approval.
      v_accounts:=public.erp_v736_item_accounting(
        p_company_id,r.item_type,r.item_id,null
      );
    end loop;
  end if;
end;
$$;

create or replace function public.erp_create_cloud_sales_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid:=gen_random_uuid();
  o public.erp_sales_orders_cloud%rowtype;
  l jsonb;
  v_number text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.create','sales.update','sales.approve']
  );
  select * into o
  from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id
    and status='approved' and not is_deleted
  for update;
  if not found then raise exception 'approved_sales_order_required'; end if;

  l:=public.erp_v736_active_logistics(p_company_id,p_order_id,'sales');
  if exists(
    select 1 from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id
      and module='sales' and document_type='invoice'
      and not is_deleted and status<>'cancelled'
  ) then
    raise exception 'active_sales_invoice_exists';
  end if;

  perform public.erp_v749_prepare_order_invoice_accounts(
    p_company_id,'sales',p_order_id,o.currency
  );

  v_number:=public.erp_next_document_number(
    p_company_id,'sales_invoice','SI',coalesce(o.effective_at,o.created_at)
  );
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'sales','invoice',p_order_id,v_number,
    jsonb_build_object(
      'currency',upper(o.currency),'totalAmount',o.total,
      'paidAmount',0,'remainingAmount',o.total,'paymentStatus','unpaid',
      'payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id',
      'logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds',
      'accountingOwner','invoice','currencyPreparedAt',now()
    ),coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,v_id,v_number,
    'create_invoice',null,'draft',
    'order currency independent from item cost currency'
  );
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid:=gen_random_uuid();
  o public.erp_purchase_orders_cloud%rowtype;
  l jsonb;
  v_number text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.create','purchases.update','purchases.approve']
  );
  select * into o
  from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id
    and status='approved' and not is_deleted
  for update;
  if not found then raise exception 'approved_purchase_order_required'; end if;

  l:=public.erp_v736_active_logistics(p_company_id,p_order_id,'purchases');
  if exists(
    select 1 from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id
      and module='purchases' and document_type='invoice'
      and not is_deleted and status<>'cancelled'
  ) then
    raise exception 'active_purchase_invoice_exists';
  end if;

  perform public.erp_v749_prepare_order_invoice_accounts(
    p_company_id,'purchases',p_order_id,o.currency
  );

  v_number:=public.erp_next_document_number(
    p_company_id,'purchase_invoice','PI',coalesce(o.effective_at,o.created_at)
  );
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'purchases','invoice',p_order_id,v_number,
    jsonb_build_object(
      'currency',upper(o.currency),'totalAmount',o.total,
      'paidAmount',0,'remainingAmount',o.total,'paymentStatus','unpaid',
      'payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id',
      'logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds',
      'accountingOwner','invoice','currencyPreparedAt',now()
    ),coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'purchases',p_order_id,v_id,v_number,
    'create_invoice',null,'draft',
    'order currency independent from item cost currency'
  );
  return v_id;
end;
$$;

-- Keep the large invoice posting engine unchanged, but always run the repair
-- preflight immediately before it. This repairs old partner/item bindings and
-- makes same-currency and cross-currency item orders follow one path.
create or replace function public.erp_approve_cloud_sales_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare d public.erp_commercial_workflow_documents%rowtype;
begin
  select * into d
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id
    and module='sales' and document_type='invoice' and not is_deleted;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  perform public.erp_v749_prepare_order_invoice_accounts(
    p_company_id,'sales',d.parent_id,coalesce(d.payload->>'currency','')
  );
  perform public.erp_approve_cloud_workflow_invoice(
    p_company_id,p_invoice_id,'sales'
  );
end;
$$;

create or replace function public.erp_approve_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare d public.erp_commercial_workflow_documents%rowtype;
begin
  select * into d
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id
    and module='purchases' and document_type='invoice' and not is_deleted;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  perform public.erp_v749_prepare_order_invoice_accounts(
    p_company_id,'purchases',d.parent_id,coalesce(d.payload->>'currency','')
  );
  perform public.erp_approve_cloud_workflow_invoice(
    p_company_id,p_invoice_id,'purchases'
  );
end;
$$;

revoke all on function public.erp_v749_prepare_order_invoice_accounts(uuid,text,uuid,text) from public,anon;
grant execute on function public.erp_v749_prepare_order_invoice_accounts(uuid,text,uuid,text) to authenticated,service_role;

commit;
