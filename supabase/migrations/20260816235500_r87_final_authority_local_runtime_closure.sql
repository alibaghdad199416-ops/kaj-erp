-- Quality Line ERP R87
-- Final authority/local-runtime closure.
-- Forward-only: delegated permission assignment is bounded by caller authority,
-- and composite read models honor the R84 per-user record scopes.
begin;

-- ---------------------------------------------------------------------------
-- 1. A delegated permission-scope manager may only delegate permissions that
--    already exist and that the caller currently owns. Company admins retain
--    catalog maintenance compatibility for dynamic field permissions.
--    Validation is completed before the target override is replaced.
-- ---------------------------------------------------------------------------
create or replace function public.erp_set_cloud_user_permissions(
  p_user_id text,
  p_permission_codes text[]
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_company uuid;
  v_slug text;
  v_admin boolean;
  v_code text;
  v_permission_id text;
  v_module text;
  v_codes text[]:=array[]::text[];
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null or v_company is null then raise exception 'membership_not_found'; end if;
  if not v_admin
     and not public.erp_cloud_user_has_permission(v_company,'permissions.scopes.manage') then
    raise exception 'permission_denied:permissions.scopes.manage' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_records
    where company_id=v_slug and entity_type='users' and record_id=p_user_id
      and deleted_at is null and not is_deleted
  ) then
    raise exception 'user_not_found';
  end if;

  select coalesce(array_agg(code order by code),array[]::text[])
  into v_codes
  from (
    select distinct btrim(raw_code) code
    from unnest(coalesce(p_permission_codes,array[]::text[])) raw_code
    where btrim(raw_code)<>''
  ) requested;

  -- Preflight every requested code before changing the target assignment.
  foreach v_code in array v_codes loop
    v_permission_id:=null;
    select record_id into v_permission_id
    from public.erp_records
    where company_id=v_slug and entity_type='permissions'
      and payload->>'code'=v_code and deleted_at is null and not is_deleted
    limit 1;

    if v_permission_id is null then
      if not v_admin then
        raise exception 'permission_unknown:%',v_code using errcode='42501';
      end if;
      v_permission_id:='perm-'||substr(md5(v_code),1,24);
      v_module:=split_part(v_code,'.',1);
      insert into public.erp_records(
        company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
      ) values(
        v_slug,'permissions',v_permission_id,
        jsonb_build_object(
          'id',v_permission_id,'code',v_code,'name',v_code,
          'module',v_module,'description','صلاحية تشغيلية مخصصة'
        ),false,null,now()
      )
      on conflict(company_id,entity_type,record_id) do update
        set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
    elsif not v_admin
      and not public.erp_cloud_user_has_permission(v_company,v_code) then
      raise exception 'permission_grant_exceeds_authority:%',v_code using errcode='42501';
    end if;
  end loop;

  insert into public.erp_records(
    company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
  ) values(
    v_slug,'user_permission_overrides',p_user_id,
    jsonb_build_object('userId',p_user_id,'enabled',true),false,null,now()
  )
  on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=v_slug and entity_type='user_permissions'
    and payload->>'userId'=p_user_id and deleted_at is null;

  foreach v_code in array v_codes loop
    select record_id into v_permission_id
    from public.erp_records
    where company_id=v_slug and entity_type='permissions'
      and payload->>'code'=v_code and deleted_at is null and not is_deleted
    limit 1;
    if v_permission_id is null then
      raise exception 'permission_catalog_inconsistent:%',v_code;
    end if;
    insert into public.erp_records(
      company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
    ) values(
      v_slug,'user_permissions',p_user_id||'::'||v_permission_id,
      jsonb_build_object('userId',p_user_id,'permissionId',v_permission_id),
      false,null,now()
    )
    on conflict(company_id,entity_type,record_id) do update
      set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
  end loop;
end $$;
revoke all on function public.erp_set_cloud_user_permissions(text,text[]) from public,anon;
grant execute on function public.erp_set_cloud_user_permissions(text,text[]) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 2. Partner card: enforce partner ownership first, then aggregate only visible
--    commercial records. Currency vectors stay explicit; USD and IQD never mix.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r49_business_partner_card_summary(
  p_company_id uuid,p_partner_kind text,p_partner_id text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_kind text:=lower(btrim(coalesce(p_partner_kind,'')));
  v_partner jsonb:='{}'::jsonb;
  v_partner_creator uuid;
  v_total jsonb:='{}'::jsonb;
  v_paid jsonb:='{}'::jsonb;
  v_outstanding jsonb:='{}'::jsonb;
  v_currencies jsonb:='[]'::jsonb;
  v_documents jsonb:='[]'::jsonb;
  v_default_currency text;
  v_transaction_count bigint:=0;
  v_payment_count bigint:=0;
  v_document_count bigint:=0;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_kind not in ('customer','supplier') then
    raise exception 'unsupported_partner_kind' using errcode='22023';
  end if;

  if v_kind='customer' then
    if not public.is_company_admin(p_company_id)
       and not public.erp_cloud_user_has_permission(p_company_id,'customers.view') then
      raise exception 'permission_denied:customers.view' using errcode='42501';
    end if;
    select coalesce(c.data,'{}'::jsonb),c.created_by into v_partner,v_partner_creator
    from public.erp_customers c
    where c.company_id=p_company_id and c.id=p_partner_id and not c.is_deleted
      and public.erp_r84_record_visible(p_company_id,'customers',c.created_by,null);
    if not found then raise exception 'business_partner_not_found' using errcode='P0002'; end if;

    select count(*),coalesce(sum(case when jsonb_typeof(s.data->'payments')='array'
      then jsonb_array_length(s.data->'payments') else 0 end),0)
    into v_transaction_count,v_payment_count
    from public.erp_sales s
    where s.company_id=p_company_id and not s.is_deleted
      and coalesce(s.data->>'customerId',s.data->>'clientId','')=p_partner_id
      and public.erp_r84_record_visible(p_company_id,'sales',s.created_by,null);

    select
      coalesce(jsonb_object_agg(currency,total_amount),'{}'::jsonb),
      coalesce(jsonb_object_agg(currency,paid_amount),'{}'::jsonb),
      coalesce(jsonb_object_agg(currency,outstanding_amount),'{}'::jsonb)
    into v_total,v_paid,v_outstanding
    from (
      select currency,
        sum(public.erp_try_numeric(coalesce(data->>'totalAmount',data->>'salePrice'),0)) total_amount,
        sum(public.erp_try_numeric(data->>'paidAmount',0)) paid_amount,
        sum(public.erp_try_numeric(data->>'remainingAmount',
          public.erp_try_numeric(coalesce(data->>'totalAmount',data->>'salePrice'),0)
          -public.erp_try_numeric(data->>'paidAmount',0))) outstanding_amount
      from (
        select s.data,
          case when upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''))) in ('USD','IQD')
            then upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''))) else null end currency
        from public.erp_sales s
        where s.company_id=p_company_id and not s.is_deleted
          and coalesce(s.data->>'customerId',s.data->>'clientId','')=p_partner_id
          and public.erp_r84_record_visible(p_company_id,'sales',s.created_by,null)
      ) q where currency is not null group by currency
    ) totals;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.document_date desc),'[]'::jsonb)
    into v_documents from (
      select
        coalesce(nullif(s.data->>'invoiceNumber',''),nullif(s.data->>'saleNumber',''),s.id) document_number,
        coalesce(s.data->>'saleDate',s.data->>'createdAt',s.created_at::text) document_date,
        case when upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''))) in ('USD','IQD')
          then upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''))) else null end currency,
        public.erp_try_numeric(coalesce(s.data->>'totalAmount',s.data->>'salePrice'),0) total_amount,
        public.erp_try_numeric(s.data->>'paidAmount',0) paid_amount,
        public.erp_try_numeric(s.data->>'remainingAmount',
          public.erp_try_numeric(coalesce(s.data->>'totalAmount',s.data->>'salePrice'),0)
          -public.erp_try_numeric(s.data->>'paidAmount',0)) outstanding_amount,
        coalesce(nullif(s.data->>'paymentStatus',''),nullif(s.data->>'status',''),'open') status
      from public.erp_sales s
      where s.company_id=p_company_id and not s.is_deleted
        and coalesce(s.data->>'customerId',s.data->>'clientId','')=p_partner_id
        and public.erp_r84_record_visible(p_company_id,'sales',s.created_by,null)
      order by coalesce(s.data->>'saleDate',s.data->>'createdAt',s.created_at::text) desc
      limit 12
    ) x;
  else
    if not public.is_company_admin(p_company_id)
       and not public.erp_cloud_user_has_permission(p_company_id,'suppliers.view') then
      raise exception 'permission_denied:suppliers.view' using errcode='42501';
    end if;
    select coalesce(s.data,'{}'::jsonb),s.created_by into v_partner,v_partner_creator
    from public.erp_suppliers s
    where s.company_id=p_company_id and s.id=p_partner_id and not s.is_deleted
      and public.erp_r84_record_visible(p_company_id,'suppliers',s.created_by,null);
    if not found then raise exception 'business_partner_not_found' using errcode='P0002'; end if;

    select count(*),coalesce(sum(case when jsonb_typeof(p.data->'payments')='array'
      then jsonb_array_length(p.data->'payments') else 0 end),0)
    into v_transaction_count,v_payment_count
    from public.erp_purchases p
    where p.company_id=p_company_id and not p.is_deleted
      and coalesce(p.data->>'supplierId','')=p_partner_id
      and public.erp_r84_record_visible(p_company_id,'purchases',p.created_by,null);

    select
      coalesce(jsonb_object_agg(currency,total_amount),'{}'::jsonb),
      coalesce(jsonb_object_agg(currency,paid_amount),'{}'::jsonb),
      coalesce(jsonb_object_agg(currency,outstanding_amount),'{}'::jsonb)
    into v_total,v_paid,v_outstanding
    from (
      select currency,
        sum(public.erp_try_numeric(data->>'totalAmount',0)) total_amount,
        sum(public.erp_try_numeric(data->>'paidAmount',0)) paid_amount,
        sum(public.erp_try_numeric(data->>'remainingAmount',
          public.erp_try_numeric(data->>'totalAmount',0)-public.erp_try_numeric(data->>'paidAmount',0))) outstanding_amount
      from (
        select p.data,
          case when upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''))) in ('USD','IQD')
            then upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''))) else null end currency
        from public.erp_purchases p
        where p.company_id=p_company_id and not p.is_deleted
          and coalesce(p.data->>'supplierId','')=p_partner_id
          and public.erp_r84_record_visible(p_company_id,'purchases',p.created_by,null)
      ) q where currency is not null group by currency
    ) totals;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.document_date desc),'[]'::jsonb)
    into v_documents from (
      select
        coalesce(nullif(p.data->>'invoiceNumber',''),nullif(p.data->>'purchaseNumber',''),p.id) document_number,
        coalesce(p.data->>'purchaseDate',p.data->>'createdAt',p.created_at::text) document_date,
        case when upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''))) in ('USD','IQD')
          then upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''))) else null end currency,
        public.erp_try_numeric(p.data->>'totalAmount',0) total_amount,
        public.erp_try_numeric(p.data->>'paidAmount',0) paid_amount,
        public.erp_try_numeric(p.data->>'remainingAmount',
          public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)) outstanding_amount,
        coalesce(nullif(p.data->>'paymentStatus',''),nullif(p.data->>'status',''),'open') status
      from public.erp_purchases p
      where p.company_id=p_company_id and not p.is_deleted
        and coalesce(p.data->>'supplierId','')=p_partner_id
        and public.erp_r84_record_visible(p_company_id,'purchases',p.created_by,null)
      order by coalesce(p.data->>'purchaseDate',p.data->>'createdAt',p.created_at::text) desc
      limit 12
    ) x;
  end if;

  if to_regclass('public.erp_documents') is not null then
    execute $query$
      select count(*) from public.erp_documents
      where company_id=$1 and not is_deleted
        and coalesce(data->>'partnerId',data->>'customerId',data->>'supplierId','')=$2
    $query$ into v_document_count using p_company_id,p_partner_id;
  end if;

  select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_currencies
  from (select key from jsonb_object_keys(v_total) key) c;
  v_default_currency:=case when upper(btrim(coalesce(v_partner->>'currency',''))) in ('USD','IQD')
    then upper(btrim(v_partner->>'currency')) else null end;

  return jsonb_build_object(
    'partnerKind',v_kind,'partnerId',p_partner_id,
    'accountId',coalesce(v_partner->>'ledgerAccountId',v_partner->>'accountId',
      v_partner->>'receivableAccountId',v_partner->>'payableAccountId'),
    'openingBalance',public.erp_try_numeric(coalesce(v_partner->>'openingBalance',v_partner->>'opening_balance'),0),
    'defaultCurrency',v_default_currency,'currencies',v_currencies,
    'transactionCount',v_transaction_count,'paymentCount',v_payment_count,
    'linkedDocumentCount',v_document_count,
    'transactionTotal',null,'paidTotal',null,'outstandingTotal',null,
    'transactionTotalByCurrency',v_total,'paidTotalByCurrency',v_paid,
    'outstandingTotalByCurrency',v_outstanding,'recentDocuments',v_documents
  );
end $$;
revoke all on function public.erp_r49_business_partner_card_summary(uuid,text,text) from public,anon;
grant execute on function public.erp_r49_business_partner_card_summary(uuid,text,text) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 3. Vehicle and partner 360 views are secondary read surfaces and must not
--    bypass the same record scopes enforced by list/detail RPCs.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r56_vehicle_service_card(p_company_id uuid,p_car_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_car jsonb; v_history jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and (not public.erp_cloud_user_has_permission(p_company_id,'cars.view')
       or not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view')) then
    raise exception 'permission_denied:vehicle_service_card' using errcode='42501';
  end if;
  select jsonb_build_object('id',c.id,'carNumber',c.data->>'carNumber','brand',c.data->>'brand',
    'model',c.data->>'model','year',c.data->>'year','chassis',coalesce(c.data->>'chassis',c.data->>'vin'),
    'plateNumber',c.data->>'plateNumber','color',c.data->>'color') into v_car
  from public.erp_cars c where c.company_id=p_company_id and c.id=p_car_id and not c.is_deleted
    and public.erp_r84_record_visible(p_company_id,'cars',c.created_by,null);
  if v_car is null then raise exception 'vehicle_not_found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,'orderNumber',o.order_number,'maintenanceDate',o.maintenance_date,
    'workflowStage',o.workflow_stage,'status',o.status,'pricingType',o.pricing_type,
    'customerId',o.customer_id,'customerName',o.customer_name,'currencyCode',o.currency_code,
    'salePrice',o.sale_price,'paidAmount',o.paid_amount,'invoiceNumber',o.invoice_number,
    'stockIssueNumber',o.stock_issue_number,'notes',o.notes,'cancelReason',o.cancel_reason,
    'opportunityId',o.opportunity_id,'opportunityNumber',o.opportunity_number,
    'items',coalesce((select jsonb_agg(jsonb_build_object('name',p.product_name,
      'quantity',p.quantity,'unitPrice',p.unit_price,'lineType',p.line_type) order by p.created_at)
      from public.erp_maintenance_parts p where p.company_id=o.company_id
      and p.maintenance_order_id=o.id and not p.is_deleted),'[]'::jsonb)
  ) order by o.maintenance_date desc,o.id),'[]'::jsonb) into v_history
  from public.erp_maintenance_orders o where o.company_id=p_company_id
    and o.source_car_id=p_car_id and not o.is_deleted
    and public.erp_r84_record_visible(p_company_id,'maintenance',o.created_by,null);
  return jsonb_build_object('vehicle',v_car,'maintenanceHistory',v_history);
end $$;

create or replace function public.erp_r56_business_partner_360(
  p_company_id uuid,p_partner_kind text,p_partner_id text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_kind text:=lower(btrim(coalesce(p_partner_kind,''))); v_base jsonb; v_slug text;
  v_crm jsonb:='[]'::jsonb; v_maintenance jsonb:='[]'::jsonb; v_chain jsonb:='[]'::jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_kind not in ('customer','supplier') then raise exception 'unsupported_partner_kind' using errcode='22023'; end if;
  v_base:=public.erp_r49_business_partner_card_summary(p_company_id,v_kind,p_partner_id);
  select slug into v_slug from public.companies where id=p_company_id and is_active;
  if v_kind='customer' then
    if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'customer_service.view') then
      select coalesce(jsonb_agg(r.payload order by r.updated_at desc),'[]'::jsonb) into v_crm
      from public.erp_records r where r.company_id=v_slug and r.entity_type='opportunities'
        and not r.is_deleted and r.deleted_at is null and r.payload->>'customerId'=p_partner_id
        and public.erp_r84_record_visible(p_company_id,'customer_service',null,
          coalesce(r.payload->>'createdByUserId',r.payload->>'createdBy',''));
    end if;
    if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
      select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'orderNumber',o.order_number,
        'carId',o.source_car_id,'carName',o.car_name,'maintenanceDate',o.maintenance_date,
        'workflowStage',o.workflow_stage,'currencyCode',o.currency_code,'salePrice',o.sale_price,
        'paidAmount',o.paid_amount) order by o.maintenance_date desc),'[]'::jsonb) into v_maintenance
      from public.erp_maintenance_orders o where o.company_id=p_company_id
        and o.customer_id::text=p_partner_id and not o.is_deleted
        and public.erp_r84_record_visible(p_company_id,'maintenance',o.created_by,null);
    end if;
    if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'sales.view') then
      select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'orderNumber',o.order_number,
        'status',o.status,'currency',o.currency,'total',o.total,'opportunityId',o.opportunity_id)
        order by o.created_at desc),'[]'::jsonb) into v_chain
      from public.erp_sales_orders_cloud o where o.company_id=p_company_id
        and o.customer_id=p_partner_id and not o.is_deleted
        and public.erp_r84_record_visible(p_company_id,'sales',o.created_by,null);
    end if;
  else
    if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'purchases.view') then
      select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'orderNumber',o.order_number,
        'status',o.status,'currency',o.currency,'total',o.total) order by o.created_at desc),'[]'::jsonb) into v_chain
      from public.erp_purchase_orders_cloud o where o.company_id=p_company_id
        and o.supplier_id=p_partner_id and not o.is_deleted
        and public.erp_r84_record_visible(p_company_id,'purchases',o.created_by,null);
    end if;
  end if;
  return coalesce(v_base,'{}'::jsonb)||jsonb_build_object('crmOpportunities',v_crm,
    'commercialChain',v_chain,'maintenanceHistory',v_maintenance,'profileVersion','R87');
end $$;

revoke all on function public.erp_r56_vehicle_service_card(uuid,text) from public,anon;
revoke all on function public.erp_r56_business_partner_360(uuid,text,text) from public,anon;
grant execute on function public.erp_r56_vehicle_service_card(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r56_business_partner_360(uuid,text,text) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 4. Workflow selectors and accounting/cash secondary reads obey record scope.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r49_list_cloud_active_cash_accounts(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',c.id,'name',coalesce(c.data->>'name',''),'currency',upper(c.data->>'currency'))
  from public.erp_cash_accounts c
  where c.company_id=p_company_id and not c.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_try_boolean(c.data->>'isActive',false)
    and upper(coalesce(c.data->>'currency','')) in ('USD','IQD')
    and public.erp_r84_record_visible(p_company_id,'cashbox',c.created_by,null)
  order by coalesce(c.data->>'name','')
$$;

create or replace function public.erp_r49_list_cloud_active_warehouses(p_company_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  return query
  select jsonb_build_object('id',w.id,'name',coalesce(w.data->>'name',''),'code',coalesce(w.data->>'code',''))
  from public.erp_warehouses w
  where w.company_id=p_company_id and not w.is_deleted
    and public.erp_try_boolean(w.data->>'isActive',false)
    and public.erp_r84_record_visible(p_company_id,'warehouses',w.created_by,null)
  order by coalesce(w.data->>'name','');
end $$;

create or replace function public.erp_r49_list_partner_unapplied_payments(
  p_company_id uuid,p_party_type text,p_party_id text,p_currency text
) returns setof jsonb language plpgsql stable security definer set search_path=public as $$
declare v_currency text:=upper(btrim(coalesce(p_currency,'')));
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then
    raise exception 'permission_denied:accounting.view' using errcode='42501';
  end if;
  if v_currency not in ('USD','IQD') then raise exception 'currency_required' using errcode='22023'; end if;
  return query
  select jsonb_build_object(
    'transaction_id',ct.id,
    'voucher_number',coalesce(ct.data->>'voucherNumber',ct.data->>'voucher_number',ct.id),
    'transaction_date',coalesce(ct.data->>'transactionDate',ct.data->>'transaction_date',ct.created_at::text),
    'amount',greatest(0,public.erp_v731_advance_original_amount(ct.data)-coalesce(a.allocated,0)),
    'original_amount',public.erp_v731_advance_original_amount(ct.data),
    'allocated_amount',coalesce(a.allocated,0),
    'currency',upper(coalesce(nullif(ct.data->>'accountCurrency',''),nullif(ct.data->>'invoiceCurrency',''),nullif(ct.data->>'currency',''))),
    'type',lower(coalesce(ct.data->>'type','')),'notes',coalesce(ct.data->>'notes',''),
    'party_type',coalesce(ct.data->>'partyType',ct.data->>'party_type'),
    'party_id',coalesce(ct.data->>'partyId',ct.data->>'party_id'),
    'detached_from_order_id',coalesce(ct.data->>'detachedFromOrderId',ct.data->>'detached_from_order_id'),
    'detached_from_maintenance_order_id',coalesce(ct.data->>'detachedFromMaintenanceOrderId',ct.data->>'detached_from_maintenance_order_id'),
    'journal_entry_id',coalesce(ct.data->>'journalEntryId',ct.data->>'journal_entry_id')
  )
  from public.erp_cash_transactions ct
  left join lateral (
    select coalesce(sum(x.amount),0) allocated from public.erp_partner_advance_allocations x
    where x.company_id=ct.company_id and x.cash_transaction_id=ct.id and not x.is_deleted
  ) a on true
  where ct.company_id=p_company_id and not ct.is_deleted
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
    and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))=lower(btrim(p_party_type))
    and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=coalesce(p_party_id,'')
    and upper(coalesce(nullif(ct.data->>'accountCurrency',''),nullif(ct.data->>'invoiceCurrency',''),nullif(ct.data->>'currency','')))=v_currency
    and public.erp_v731_advance_original_amount(ct.data)-coalesce(a.allocated,0)>0.001
    and public.erp_r84_record_visible(p_company_id,'cashbox',ct.created_by,null)
  order by coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at) desc,ct.created_at desc;
end $$;

create or replace function public.erp_r49_get_commercial_order_allocation_context(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_context jsonb; v_warehouses jsonb; v_creator uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if p_module='sales' then
    if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'sales.view') then
      raise exception 'permission_denied:sales.view' using errcode='42501';
    end if;
    select created_by into v_creator from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    if not found or not public.erp_r84_record_visible(p_company_id,'sales',v_creator,null) then
      raise exception 'record_scope_denied:sales.records.own' using errcode='42501';
    end if;
  elsif p_module='purchases' then
    if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'purchases.view') then
      raise exception 'permission_denied:purchases.view' using errcode='42501';
    end if;
    select created_by into v_creator from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    if not found or not public.erp_r84_record_visible(p_company_id,'purchases',v_creator,null) then
      raise exception 'record_scope_denied:purchases.records.own' using errcode='42501';
    end if;
  else
    raise exception 'invalid workflow module' using errcode='22023';
  end if;

  v_context:=public.erp_get_commercial_order_allocation_context(p_company_id,p_order_id,p_module);
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',w.id,'name',coalesce(w.data->>'name',w.data->>'code',w.id),
    'code',w.data->>'code','address',w.data->>'address'
  ) order by coalesce(w.data->>'name',w.data->>'code',w.id)),'[]'::jsonb)
  into v_warehouses from public.erp_warehouses w
  where w.company_id=p_company_id and not w.is_deleted
    and public.erp_try_boolean(w.data->>'isActive',false)
    and public.erp_r84_record_visible(p_company_id,'warehouses',w.created_by,null);
  return jsonb_set(v_context,'{warehouses}',v_warehouses,true);
end $$;

revoke all on function public.erp_r49_list_cloud_active_cash_accounts(uuid) from public,anon;
revoke all on function public.erp_r49_list_cloud_active_warehouses(uuid) from public,anon;
revoke all on function public.erp_r49_list_partner_unapplied_payments(uuid,text,text,text) from public,anon;
revoke all on function public.erp_r49_get_commercial_order_allocation_context(uuid,uuid,text) from public,anon;
grant execute on function public.erp_r49_list_cloud_active_cash_accounts(uuid) to authenticated,service_role;
grant execute on function public.erp_r49_list_cloud_active_warehouses(uuid) to authenticated,service_role;
grant execute on function public.erp_r49_list_partner_unapplied_payments(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_get_commercial_order_allocation_context(uuid,uuid,text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
