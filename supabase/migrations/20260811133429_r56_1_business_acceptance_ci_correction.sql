-- R56.1 forward-only business acceptance correction. Migration 260 remains
-- immutable. This release relaxes only the optional opportunity-car match and
-- expands customer-safe aggregated read models.
begin;

create or replace function public.erp_r56_validate_maintenance_relationship()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_slug text; v_opportunity jsonb; v_car_id text; v_customer_id text;
begin
  if tg_op='UPDATE' and
     (new.source_car_id is distinct from old.source_car_id or new.car_id is distinct from old.car_id) then
    raise exception 'maintenance_vehicle_immutable' using errcode='22023';
  end if;
  if not exists(select 1 from public.erp_cars c where c.company_id=new.company_id
      and c.id=new.source_car_id and not c.is_deleted) then
    raise exception 'maintenance_vehicle_company_mismatch' using errcode='23503';
  end if;
  if nullif(btrim(coalesce(new.opportunity_id,'')),'') is null then return new; end if;
  select c.slug into v_slug from public.companies c where c.id=new.company_id and c.is_active;
  select r.payload into v_opportunity from public.erp_records r
  where r.company_id=v_slug and r.entity_type='opportunities'
    and r.record_id=new.opportunity_id and not r.is_deleted and r.deleted_at is null;
  if v_opportunity is null then
    raise exception 'maintenance_opportunity_not_found' using errcode='23503';
  end if;
  v_car_id:=nullif(btrim(coalesce(v_opportunity->>'carId','')),'');
  v_customer_id:=nullif(btrim(coalesce(v_opportunity->>'customerId','')),'');
  if v_car_id is not null and v_car_id<>new.source_car_id then
    raise exception 'maintenance_opportunity_vehicle_mismatch' using errcode='23514';
  end if;
  if v_customer_id is not null and v_customer_id<>coalesce(new.customer_id::text,'') then
    raise exception 'maintenance_opportunity_customer_mismatch' using errcode='23514';
  end if;
  new.opportunity_number:=coalesce(nullif(v_opportunity->>'opportunityNumber',''),new.opportunity_id);
  return new;
end $$;
revoke all on function public.erp_r56_validate_maintenance_relationship() from public,anon,authenticated;
grant execute on function public.erp_r56_validate_maintenance_relationship() to service_role;

create or replace function public.erp_r56_vehicle_service_card(p_company_id uuid,p_car_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_car jsonb; v_history jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and
     (not public.erp_cloud_user_has_permission(p_company_id,'cars.view') or
      not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view')) then
    raise exception 'permission_denied:vehicle_service_card' using errcode='42501';
  end if;
  select jsonb_build_object('id',c.id,'carNumber',c.data->>'carNumber',
    'brand',c.data->>'brand','model',c.data->>'model','year',c.data->>'year',
    'chassis',coalesce(c.data->>'chassis',c.data->>'vin'),'plateNumber',c.data->>'plateNumber',
    'color',c.data->>'color','vehicleType',c.data->>'vehicleType','status',c.data->>'status',
    'warehouseId',c.data->>'warehouseId','warehouseName',c.data->>'warehouseName',
    'customerName',c.data->>'customerName','purchaseReference',c.data->>'purchaseNumber',
    'salesReference',coalesce(c.data->>'salesOrderNumber',c.data->>'saleNumber'),
    'imagePath',c.data->>'imagePath') into v_car
  from public.erp_cars c where c.company_id=p_company_id and c.id=p_car_id and not c.is_deleted;
  if v_car is null then raise exception 'vehicle_not_found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,'orderNumber',o.order_number,'carId',o.source_car_id,'carName',o.car_name,
    'isSoldCar',o.is_sold_car,'opportunityId',o.opportunity_id,
    'opportunityNumber',o.opportunity_number,'maintenanceDate',o.maintenance_date,
    'createdAt',o.created_at,'updatedAt',o.updated_at,'workflowStage',o.workflow_stage,
    'status',o.status,'pricingType',o.pricing_type,'customerId',o.customer_id,
    'customerName',o.customer_name,'currencyCode',o.currency_code,'salePrice',o.sale_price,
    'paidAmount',o.paid_amount,'paymentStatus',case when o.sale_price<=o.paid_amount then 'paid'
      when o.paid_amount>0 then 'partial' else 'unpaid' end,
    'warehouseId',o.source_warehouse_id,'warehouseName',w.data->>'name',
    'stockIssueNumber',o.stock_issue_number,'stockIssueStatus',case when o.stock_issue_number is null then null
      when o.workflow_stage in ('stock_issue_approved','invoice_draft','invoice_approved','paid','completed') then 'approved' else 'draft' end,
    'invoiceNumber',o.invoice_number,'invoiceStatus',case when o.invoice_number is null then null
      when o.workflow_stage in ('invoice_approved','paid','completed') then 'approved' else 'draft' end,
    'notes',o.notes,'cancelReason',o.cancel_reason,'cancelledAt',o.cancelled_at,
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'productId',p.source_product_id,
      'name',p.product_name,'productName',p.product_name,'quantity',p.quantity,'unitPrice',p.unit_price,
      'lineTotal',p.line_total_price,'lineType',p.line_type,'warehouseId',p.source_warehouse_id,
      'warehouseName',pw.data->>'name') order by p.created_at)
      from public.erp_maintenance_parts p left join public.erp_warehouses pw
        on pw.company_id=p.company_id and pw.id=p.source_warehouse_id and not pw.is_deleted
      where p.company_id=o.company_id and p.maintenance_order_id=o.id and not p.is_deleted),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(jsonb_build_object('id',mp.id,'amount',mp.amount,
      'currencyCode',mp.currency_code,'paymentDate',mp.payment_date,'notes',mp.notes) order by mp.payment_date)
      from public.erp_maintenance_payments mp where mp.company_id=o.company_id
       and mp.maintenance_order_id=o.id and not mp.is_deleted),'[]'::jsonb)
  ) order by o.maintenance_date desc,o.id),'[]'::jsonb) into v_history
  from public.erp_maintenance_orders o left join public.erp_warehouses w
    on w.company_id=o.company_id and w.id=o.source_warehouse_id and not w.is_deleted
  where o.company_id=p_company_id and o.source_car_id=p_car_id and not o.is_deleted;
  return jsonb_build_object('vehicle',v_car,'maintenanceHistory',v_history);
end $$;

create or replace function public.erp_r56_business_partner_360(
  p_company_id uuid,p_partner_kind text,p_partner_id text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_kind text:=lower(btrim(coalesce(p_partner_kind,''))); v_base jsonb; v_slug text;
 v_opportunities jsonb:='[]'; v_maintenance jsonb:='[]'; v_chain jsonb:='[]';
 v_accounts jsonb:='[]'; v_ledger jsonb:='[]'; v_projected jsonb:='[]';
begin
  perform public.erp_active_company_context(p_company_id);
  if v_kind not in ('customer','supplier') then raise exception 'unsupported_partner_kind' using errcode='22023'; end if;
  v_base:=public.erp_r49_business_partner_card_summary(p_company_id,v_kind,p_partner_id);
  select slug into v_slug from public.companies where id=p_company_id and is_active;
  if v_kind='customer' and (public.is_company_admin(p_company_id) or
      public.erp_cloud_user_has_permission(p_company_id,'customer_service.view')) then
    v_projected:=public.erp_r49_opportunity_command('list','{}'::jsonb);
    select coalesce(jsonb_agg(value||jsonb_build_object(
      'entityType','opportunity','documentNumber',value->>'opportunityNumber',
      'date',value->>'createdAt')),'[]'::jsonb) into v_opportunities
      from jsonb_array_elements(v_projected) where value->>'customerId'=p_partner_id;
  end if;
  if v_kind='customer' and (public.is_company_admin(p_company_id) or
      public.erp_cloud_user_has_permission(p_company_id,'maintenance.view')) then
    select coalesce(jsonb_agg(jsonb_build_object('entityType','maintenance','id',o.id,
      'documentNumber',o.order_number,'parentId',o.opportunity_id,'status',o.workflow_stage,
      'date',o.maintenance_date,'currency',o.currency_code,'total',o.sale_price,
      'paid',o.paid_amount,'outstanding',greatest(o.sale_price-o.paid_amount,0),
      'carId',o.source_car_id,'carName',o.car_name) order by o.maintenance_date desc),'[]'::jsonb)
      into v_maintenance from public.erp_maintenance_orders o where o.company_id=p_company_id
      and o.customer_id::text=p_partner_id and not o.is_deleted;
  end if;
  if (v_kind='customer' and (public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'sales.view')))
     or (v_kind='supplier' and (public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'purchases.view'))) then
    select coalesce(jsonb_agg(row_data order by row_date desc),'[]'::jsonb) into v_chain from (
      select jsonb_build_object('entityType',case when v_kind='customer' then 'sales_order' else 'purchase_order' end,
        'id',o.id,'parentId',null,'documentNumber',o.order_number,'status',o.status,'date',o.created_at,
        'currency',o.currency,'total',o.total,'paid',0,'outstanding',o.total) row_data,o.created_at row_date
      from (select id,order_number,status,currency,total,created_at,customer_id partner_id from public.erp_sales_orders_cloud
            where v_kind='customer' and company_id=p_company_id and not is_deleted
            union all select id,order_number,status,currency,total,created_at,supplier_id from public.erp_purchase_orders_cloud
            where v_kind='supplier' and company_id=p_company_id and not is_deleted) o where o.partner_id=p_partner_id
      union all
      select jsonb_build_object('entityType',d.module||'_'||d.document_type,'id',d.id,'parentId',d.parent_id,
        'documentNumber',d.document_number,'status',d.status,'date',d.created_at,
        'currency',coalesce(d.payload->>'currencyCode',d.payload->>'currency'),
        'total',public.erp_try_numeric(d.payload->>'totalAmount',0),'paid',public.erp_try_numeric(d.payload->>'paidAmount',0),
        'outstanding',public.erp_try_numeric(d.payload->>'remainingAmount',0)),d.created_at
      from public.erp_commercial_workflow_documents d
      join (select id,customer_id partner_id from public.erp_sales_orders_cloud where v_kind='customer' and company_id=p_company_id and not is_deleted
            union all select id,supplier_id from public.erp_purchase_orders_cloud where v_kind='supplier' and company_id=p_company_id and not is_deleted) po
        on po.id=d.parent_id and po.partner_id=p_partner_id
      where d.company_id=p_company_id and d.module=case when v_kind='customer' then 'sales' else 'purchases' end and not d.is_deleted
    ) chain;
  end if;
  if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then
    select coalesce(jsonb_agg(jsonb_build_object('accountId',a.account_id,'accountCode',a.code,
      'accountName',a.name,'currencyCode',a.currency,'openingBalance',a.opening_balance,
      'debit',coalesce(j.debit,0),'credit',coalesce(j.credit,0),
      'currentBalance',a.opening_balance+coalesce(j.debit,0)-coalesce(j.credit,0)) order by a.currency),'[]'::jsonb)
    into v_accounts from public.erp_partner_accounts pa
    join public.erp_accounts a on a.organization_id=pa.organization_id and
      a.account_id in (pa.usd_account_id,pa.iqd_account_id) and a.is_active
    left join lateral (select sum(public.erp_try_numeric(l.data->>'debit',0)) debit,
      sum(public.erp_try_numeric(l.data->>'credit',0)) credit from public.erp_journal_lines l
      where l.company_id=p_company_id and not l.is_deleted and l.data->>'accountId'=a.account_id) j on true
    where pa.organization_id=p_company_id and pa.partner_type=v_kind and pa.partner_id=p_partner_id and pa.is_active;
    select coalesce(jsonb_agg(jsonb_build_object('entryId',l.data->>'entryId','id',l.id,
      'date',coalesce(l.data->>'date',e.data->>'date'),
      'entryNumber',coalesce(e.data->>'entryNumber',e.data->>'journalNumber',l.data->>'entryId'),
      'documentType',e.data->>'referenceType','documentReference',e.data->>'referenceId',
      'debit',public.erp_try_numeric(l.data->>'debit',0),'credit',public.erp_try_numeric(l.data->>'credit',0),
      'currency',a.currency,'description',l.data->>'description') order by l.updated_at desc),'[]'::jsonb)
    into v_ledger from public.erp_partner_accounts pa join public.erp_accounts a
      on a.organization_id=pa.organization_id and a.account_id in(pa.usd_account_id,pa.iqd_account_id)
    join public.erp_journal_lines l on l.company_id=p_company_id and not l.is_deleted and l.data->>'accountId'=a.account_id
    left join public.erp_journal_entries e on e.company_id=l.company_id and e.id=coalesce(l.data->>'entryId','') and not e.is_deleted
    where pa.organization_id=p_company_id and pa.partner_type=v_kind and pa.partner_id=p_partner_id and pa.is_active;
  end if;
  return coalesce(v_base,'{}')||jsonb_build_object('crmOpportunities',v_opportunities,
    'maintenanceHistory',v_maintenance,'commercialChain',v_chain,'accountsByCurrency',v_accounts,
    'ledgerMovements',v_ledger,'profileVersion','R56.1');
end $$;

revoke all on function public.erp_r56_vehicle_service_card(uuid,text) from public,anon;
revoke all on function public.erp_r56_business_partner_360(uuid,text,text) from public,anon;
grant execute on function public.erp_r56_vehicle_service_card(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r56_business_partner_360(uuid,text,text) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
