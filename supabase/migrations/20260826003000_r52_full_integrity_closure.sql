begin;

-- R52: consolidated database integrity closure.
-- This migration is additive/replace-only: historical migrations remain intact,
-- financial data is untouched, and only broken runtime contracts are corrected.

-- The document-processing queue is part of the contract/document workflow and
-- must exist before R9 monitor functions are compiled on a clean database.
create table if not exists public.erp_document_processing_jobs (like public.erp_contracts including all);
create index if not exists erp_doc_job_status_idx_r52
  on public.erp_document_processing_jobs(company_id,((data->>'status')),created_at);
alter table public.erp_document_processing_jobs enable row level security;
do $$
begin
  execute 'drop policy if exists tenant_access on public.erp_document_processing_jobs';
  execute 'create policy tenant_access on public.erp_document_processing_jobs for all using (erp_user_belongs_to_company(company_id)) with check (erp_user_belongs_to_company(company_id))';
exception when undefined_function then null;
end $$;

-- Correct volatility declarations. These routines perform time-dependent or
-- volatile work and therefore must not be advertised as STABLE/IMMUTABLE.
alter function public.erp_try_date(text,date) stable;
alter function public.erp_try_timestamptz(text,timestamptz) stable;
alter function public.erp_search_cloud_documents(uuid,text,integer) volatile;
alter function public.erp_r22_cash_health(uuid) volatile;
alter function public.erp_v2300_get_commercial_order_complete_details(uuid,uuid) volatile;
alter function public.erp_r9_cloud_reports_summary(uuid,date) volatile;
alter function public.erp_r9_cloud_dashboard_snapshot(uuid,date) volatile;
alter function public.erp_r9_cloud_cash_currency_summary(uuid,date) volatile;
alter function public.erp_r9_cloud_trial_balance(uuid,date) volatile;
alter function public.erp_r9_cloud_account_balance_before(uuid,uuid,date) volatile;
alter function public.erp_r9_cloud_detailed_accounting_report(uuid,date,date) volatile;
alter function public.erp_r9_cloud_cash_flow_hierarchy(uuid,date,date) volatile;
alter function public.erp_r9_cloud_contextual_report(uuid,jsonb) volatile;
alter function public.erp_r9_cloud_model_report(uuid,jsonb) volatile;
alter function public.erp_r9_cloud_customer_service_report(uuid,jsonb) volatile;
alter function public.erp_r9_cloud_report_audit(uuid,date,date) volatile;
alter function public.erp_r49_get_sales_order_draft(uuid,uuid) volatile;
alter function public.erp_r49_get_purchase_order_draft(uuid,uuid) volatile;
alter function public.erp_get_cloud_current_document_blob(uuid,uuid) volatile;
alter function public.erp_get_cloud_document(uuid,uuid) volatile;
alter function public.erp_list_cloud_document_versions(uuid,uuid) volatile;
alter function public.erp_list_cloud_document_permissions(uuid,uuid) volatile;
alter function public.erp_r15_current_state_health(uuid) volatile;
alter function public.erp_r9_cloud_reports_summary(uuid,date) volatile;
alter function public.erp_r49_get_sales_order_draft(uuid,uuid) volatile;
alter function public.erp_r49_get_purchase_order_draft(uuid,uuid) volatile;

-- Dynamic-record lint false positives are removed by using scalar targets. The
-- runtime SQL remains parameterized and identifier-safe.
create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,p_table text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_rel regclass;
  v_id text;
  v_data jsonb;
  v_version bigint;
  v_updated_at timestamptz;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table using errcode='22023';
  end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then raise exception 'master_table_not_found:%',p_table using errcode='42P01'; end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null or (not public.erp_cloud_user_has_permission(p_company_id,v_permission) and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  for v_id,v_data,v_version,v_updated_at in execute format(
    'select id::text,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,version,updated_at from public.%I r where company_id=$1 and not coalesce(is_deleted,false) and not public.erp_r15_pending_delete_exists($1,$2,r.id) order by updated_at desc',
    p_table
  ) using p_company_id,p_table loop
    return next public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_data)
      ||jsonb_build_object('id',v_id,'_cloudVersion',v_version,'_cloudUpdatedAt',v_updated_at);
  end loop;
  return;
end;
$$;

create or replace function public.erp_r9_get_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_rel regclass;
  v_id text;
  v_data jsonb;
  v_version bigint;
  v_updated_at timestamptz;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table using errcode='22023';
  end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then raise exception 'master_table_not_found:%',p_table using errcode='42P01'; end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null or (not public.erp_cloud_user_has_permission(p_company_id,v_permission) and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;
  if public.erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id) then return null; end if;

  execute format(
    'select id::text,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,version,updated_at from public.%I where company_id=$1 and id=$2 and not coalesce(is_deleted,false)',p_table
  ) into v_id,v_data,v_version,v_updated_at using p_company_id,p_record_id;
  if v_id is null then return null; end if;
  return public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_data)
    ||jsonb_build_object('id',v_id,'_cloudVersion',v_version,'_cloudUpdatedAt',v_updated_at);
end;
$$;

-- R15 reconciliation uses one table name per dynamic statement. PostgreSQL does
-- not support treating an array of identifiers as a single relation name.
create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_table text;
  v_tables text[]:=array['erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images'];
  v_total bigint:=0;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  foreach v_table in array v_tables loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones t on t.company_id=r.company_id and t.source_table=$2 and t.record_id=r.id::text where r.company_id=$1 and t.restored_at is null and not coalesce(r.is_deleted,false)',v_table
      ) into v_total using p_company_id,v_table;
    end if;
  end loop;
  return jsonb_build_object('companyId',p_company_id,'checkedTables',v_tables,'openCanonicalConflicts',v_total,'status','ok');
end;
$$;

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path=public as $$
declare
  v_table text;
  v_tables text[]:=array['erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images'];
  v_conflicts bigint:=0;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  foreach v_table in array v_tables loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones t on t.company_id=r.company_id and t.source_table=$2 and t.record_id=r.id::text where r.company_id=$1 and t.restored_at is null and not coalesce(r.is_deleted,false)',v_table
      ) into v_conflicts using p_company_id,v_table;
    end if;
  end loop;
  return jsonb_build_object('companyId',p_company_id,'canonicalConflicts',v_conflicts,'checkedTables',v_tables,'healthy',v_conflicts=0);
end;
$$;

-- The original R49 opportunity query referenced a physical created_at column
-- that erp_records does not expose. Keep the search result contract but derive
-- the date only from payload/updated_at.
create or replace function public.erp_r49_cloud_global_search(
  p_company_id uuid,p_query text,p_limit integer default 50
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_slug text;
  v_limit integer:=greatest(1,least(coalesce(p_limit,50),200));
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_query,'')))<2 then return; end if;
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then raise exception 'company_not_found' using errcode='P0002'; end if;
  return query
  with base as (
    select case when b.row_payload->>'type'='القيود المحاسبية' then
      jsonb_set(b.row_payload,'{status}',to_jsonb(coalesce((select nullif(j.data->>'status','') from public.erp_journal_entries j where j.company_id=p_company_id and j.id::text=b.row_payload->>'id' and not j.is_deleted limit 1),'unknown')),true)
      else b.row_payload end row_payload,20 rank
    from public.erp_r9_cloud_global_search(p_company_id,p_query,v_limit) b(row_payload)
  ), enriched as (
    select case when public.erp_r49_search_result_currency(p_company_id,row_payload) is null then row_payload else row_payload||jsonb_build_object('currency',public.erp_r49_search_result_currency(p_company_id,row_payload)) end row_payload,rank
    from base
  ), opportunities as (
    select jsonb_build_object(
      'id',r.record_id,'type','الفرص التجارية',
      'title',coalesce(nullif(r.payload->>'title',''),nullif(r.payload->>'opportunityNumber',''),'فرصة تجارية'),
      'subtitle',concat_ws(' • ',nullif(r.payload->>'opportunityNumber',''),nullif(r.payload->>'customerName',''),nullif(r.payload->>'stage','')),
      'route','/customer-service','permission','customer_service.view','icon','opportunity',
      'status',coalesce(nullif(r.payload->>'status',''),nullif(r.payload->>'stage',''),'pending'),
      'amount',public.erp_try_numeric(r.payload->>'expectedValue',0),
      'currency',case when upper(coalesce(r.payload->>'currency','')) in ('USD','IQD') then upper(r.payload->>'currency') else null end,
      'date',coalesce(nullif(r.payload->>'updatedAt',''),nullif(r.payload->>'createdAt',''),r.updated_at::text)
    ) row_payload,10 rank
    from public.erp_records r
    where r.company_id=v_slug and r.entity_type='opportunities' and r.deleted_at is null
      and (public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'customer_service.view'))
      and (coalesce(r.payload->>'opportunityNumber','') ilike '%'||btrim(p_query)||'%' or coalesce(r.payload->>'title','') ilike '%'||btrim(p_query)||'%' or coalesce(r.payload->>'customerName','') ilike '%'||btrim(p_query)||'%' or coalesce(r.payload->>'customerPhone','') ilike '%'||btrim(p_query)||'%' or coalesce(r.payload->>'stage','') ilike '%'||btrim(p_query)||'%' or coalesce(r.payload->>'status','') ilike '%'||btrim(p_query)||'%')
  )
  select x.row_payload from (select row_payload,rank from opportunities union all select row_payload,rank from enriched) x
  order by x.rank,coalesce(x.row_payload->>'date','') desc limit v_limit;
end;
$$;

-- Phase-3 maintenance lines already consume JSONB; explicitly normalize callers
-- that may have historically passed text-shaped values.
create or replace function public.erp_phase3_prepare_maintenance_lines(
  p_company_id uuid,p_order_id uuid,p_currency text,p_lines jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  x jsonb;
  v_product text; v_warehouse text; v_qty numeric; v_name text; v_cost numeric; v_price numeric;
  v_available numeric; v_type text; v_stock public.erp_warehouse_stock%rowtype;
  v_cost_total numeric:=0; v_price_total numeric:=0; v_seen text[]:=array[]::text[];
begin
  if upper(coalesce(p_currency,'')) not in ('USD','IQD') then raise exception 'عملة أمر الصيانة غير مدعومة'; end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'أضف بند صيانة واحداً على الأقل'; end if;
  update public.erp_maintenance_parts set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
  for x in select value from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) loop
    v_product:=nullif(x->>'product_id',''); v_warehouse:=nullif(x->>'warehouse_id','');
    v_qty:=public.erp_try_numeric(x->>'quantity',0); v_price:=public.erp_try_numeric(x->>'unit_price',0);
    if v_product is null or v_qty<=0 or trunc(v_qty)<>v_qty or v_price<0 then raise exception 'بيانات بند الصيانة غير صحيحة'; end if;
    if v_product=any(v_seen) then raise exception 'لا يمكن تكرار المادة أو الخدمة في أمر الصيانة'; end if;
    v_seen:=array_append(v_seen,v_product);
    select coalesce(data->>'name',data->>'nameAr'),lower(coalesce(data->>'itemType',data->>'item_type','stock')),public.erp_try_numeric(data->>'unitCost',data->>'purchasePrice') into v_name,v_type,v_cost from public.erp_inventory where company_id=p_company_id and id=v_product and not is_deleted and coalesce((data->>'isActive')::boolean,true);
    if not found then raise exception 'بند الصيانة غير موجود أو غير فعال'; end if;
    if v_type='service' then v_warehouse:=null; v_cost:=0;
    else
      if v_warehouse is null then raise exception 'يجب اختيار مخزن لكل مادة مخزنية'; end if;
      if not exists(select 1 from public.erp_warehouses where company_id=p_company_id and id=v_warehouse and not is_deleted) then raise exception 'مخزن السحب غير موجود'; end if;
      select * into v_stock from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=v_warehouse and data->>'productId'=v_product for update;
      v_available:=case when found then public.erp_try_numeric(v_stock.data->>'quantity',0) else 0 end;
      if v_available<v_qty then raise exception 'الرصيد غير كافٍ للمادة %',coalesce(v_name,v_product); end if;
      if found and public.erp_try_numeric(v_stock.data->>'averageUnitCost',0)>0 then v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0); end if;
      perform public.erp_phase2_item_accounts(p_company_id,'product',v_product,upper(p_currency));
    end if;
    insert into public.erp_maintenance_parts(company_id,maintenance_order_id,product_id,product_name,warehouse_id,quantity,unit_cost,total_cost,line_type,unit_price,line_total_price)
    values(p_company_id,p_order_id,v_product::uuid,coalesce(v_name,v_product),case when v_warehouse is null then null else v_warehouse::uuid end,v_qty::integer,coalesce(v_cost,0),coalesce(v_cost,0)*v_qty,v_type,v_price,v_price*v_qty);
    v_cost_total:=v_cost_total+coalesce(v_cost,0)*v_qty; v_price_total:=v_price_total+v_price*v_qty;
  end loop;
  return jsonb_build_object('costTotal',v_cost_total,'priceTotal',v_price_total);
end;
$$;

notify pgrst,'reload schema';
commit;
