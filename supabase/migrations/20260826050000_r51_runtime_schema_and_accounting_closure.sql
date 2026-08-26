begin;

-- R51: large forward-only runtime closure package.
-- Data-preserving: no historical migration is edited and no business rows are deleted.

-- ---------------------------------------------------------------------------
-- Canonical master reads: avoid anonymous RECORD + dynamic SQL. PostgreSQL's
-- lint checker cannot determine the tuple shape of a RECORD returned by EXECUTE.
-- Scalar targets keep the same runtime behavior while making the contract
-- statically verifiable.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,p_table text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_id text;
  v_data jsonb;
  v_version bigint;
  v_updated_at timestamptz;
  v_rel regclass;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table using errcode='22023';
  end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then
    raise exception 'master_table_not_found:%',p_table using errcode='42P01';
  end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null or
     (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
      and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  for v_id,v_data,v_version,v_updated_at in execute format(
    'select id::text,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,version,updated_at '
    ||'from public.%I where company_id=$1 and not coalesce(is_deleted,false) '
    ||'and not public.erp_r15_pending_delete_exists($1,$2,id) order by updated_at desc',p_table
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
  v_id text;
  v_data jsonb;
  v_version bigint;
  v_updated_at timestamptz;
  v_rel regclass;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table using errcode='22023';
  end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then
    raise exception 'master_table_not_found:%',p_table using errcode='42P01';
  end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null or
     (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
      and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;
  if public.erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id) then return null; end if;

  execute format(
    'select id::text,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,version,updated_at '
    ||'from public.%I where company_id=$1 and id=$2 and not coalesce(is_deleted,false)',p_table
  ) into v_id,v_data,v_version,v_updated_at using p_company_id,p_record_id;
  if v_id is null then return null; end if;
  return public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_data)
    ||jsonb_build_object('id',v_id,'_cloudVersion',v_version,'_cloudUpdatedAt',v_updated_at);
end;
$$;

-- ---------------------------------------------------------------------------
-- R15 reconciliation: never quote a table-array as one identifier. Each table
-- is resolved independently and absent optional tables are skipped.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_table text;
  v_touched bigint:=0;
  v_scanned bigint:=0;
  v_company_slug text;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;

  select slug into v_company_slug from public.companies where id=p_company_id;
  if v_company_slug is null then raise exception 'company_not_found'; end if;

  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'select count(*) from public.%I r where r.company_id=$1',v_table
      ) into v_scanned using p_company_id;
      v_scanned:=v_scanned+0;

      execute format(
        'update public.%I r set is_deleted=true, '
        ||'deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=coalesce(r.version,0)+1 '
        ||'where r.company_id=$1 and not coalesce(r.is_deleted,false) '
        ||'and public.erp_r15_pending_delete_exists($1,$2,r.id)',v_table
      ) using p_company_id,v_table;
      get diagnostics v_touched = row_count;
    end if;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'companyId',p_company_id,
    'companySlug',v_company_slug,
    'scanned',v_scanned,
    'reconciled',v_touched,
    'checkedAt',timezone('utc',now()),
    'stateVersion',15
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- R16 health: dynamic relation names are passed through %I one table at a time.
-- This removes the malformed public."{a,b,c}" relation generated by the old
-- implementation and remains safe if an optional master table is absent.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb:='{}'::jsonb;
  v_open_issues bigint:=0;
  v_tombstones bigint:=0;
  v_conflicts bigint:=0;
  v_table text;
  v_count bigint;
  v_issue_details jsonb:='[]'::jsonb;
begin
  if auth.uid() is not null and not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if to_regprocedure('public.erp_r15_current_state_health(uuid)') is not null then
    v_base:=coalesce(public.erp_r15_current_state_health(p_company_id),'{}'::jsonb);
  end if;

  select count(*) into v_open_issues
  from public.erp_canonical_reconciliation_issues
  where company_id=p_company_id and resolved_at is null;
  select count(*) into v_tombstones
  from public.erp_canonical_deletion_tombstones
  where company_id=p_company_id and restored_at is null;
  select coalesce(jsonb_agg(jsonb_build_object(
      'issueType',q.issue_type,'entityType',q.entity_type,'entityId',q.entity_id,
      'details',q.details,'firstSeenAt',q.first_seen_at,'lastSeenAt',q.last_seen_at
    ) order by q.last_seen_at desc),'[]'::jsonb)
    into v_issue_details
  from (
    select issue_type,entity_type,entity_id,details,first_seen_at,last_seen_at
    from public.erp_canonical_reconciliation_issues
    where company_id=p_company_id and resolved_at is null
    order by last_seen_at desc limit 25
  ) q;

  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones t '
        ||'on t.company_id=r.company_id and t.source_table=$2 and t.record_id=r.id::text '
        ||'where r.company_id=$1 and t.restored_at is null and not coalesce(r.is_deleted,false)',v_table
      ) into v_count using p_company_id,v_table;
      v_conflicts:=v_conflicts+coalesce(v_count,0);
    end if;
  end loop;

  return v_base||jsonb_build_object(
    'ok',coalesce((v_base->>'ok')::boolean,true) and v_open_issues=0 and v_conflicts=0,
    'persistentDeletionConflictCount',v_conflicts,
    'permanentDeletionTombstoneCount',v_tombstones,
    'unresolvedCanonicalReconciliationIssueCount',v_open_issues,
    'openCanonicalIssues',v_issue_details,
    'canonicalStateVersion',16,
    'checkedAt',timezone('utc',now())
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Scrap accounting: initialize JSONB explicitly. The previous text literal
-- caused PostgreSQL assignment-cast lint failure before the function could run.
-- ---------------------------------------------------------------------------
create or replace function public.erp_phase2_post_scrap(
 p_company_id uuid,p_warehouse_id text,p_reference_id text,p_currency text,
 p_items jsonb,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare
  w public.erp_warehouses%rowtype;
  i jsonb;
  ac jsonb;
  qty numeric;
  cost numeric;
  amount numeric;
  lines jsonb:='[]'::jsonb;
  expense text;
  eid text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into w from public.erp_warehouses
  where company_id=p_company_id and id=p_warehouse_id and not is_deleted for update;
  if not found then raise exception 'مخزن التوالف غير موجود'; end if;
  expense:=nullif(coalesce(w.data->>'scrapExpenseAccountId',w.data->>'scrap_expense_account_id'),'');
  perform public.erp_phase2_account_guard(p_company_id,expense,'expense',p_currency);
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception 'items must be an array'; end if;
  for i in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    qty:=public.erp_try_numeric(i->>'quantity',0);
    if qty<=0 then raise exception 'كمية التلف غير صحيحة'; end if;
    ac:=public.erp_phase2_item_accounts(p_company_id,coalesce(i->>'itemType','product'),i->>'itemId',p_currency);
    if coalesce(i->>'itemType','product')='car' then
      select public.erp_try_numeric(data->>'purchasePrice',0) into cost
      from public.erp_cars where company_id=p_company_id and id=i->>'itemId';
    else
      select public.erp_try_numeric(data->>'averageUnitCost',public.erp_try_numeric(data->>'purchasePrice',0)) into cost
      from public.erp_inventory where company_id=p_company_id and id=i->>'itemId';
    end if;
    amount:=qty*coalesce(cost,0);
    lines:=lines||jsonb_build_array(
      jsonb_build_object('accountId',expense,'debit',amount,'credit',0,'description','تالف/استهلاك '||coalesce(i->>'description',i->>'itemId')),
      jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',amount,'description','إخراج أصل مخزني')
    );
  end loop;
  if jsonb_array_length(lines)=0 then return null; end if;
  eid:=public.erp_phase2_insert_journal(
    p_company_id,'inventory_scrap',p_reference_id,'SCRAP-'||replace(p_reference_id,'-',''),
    'قيد تلف واستهلاك '||coalesce(p_notes,''),p_currency,lines
  );
  return eid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Correct volatility declarations in bulk. A routine that calls a VOLATILE
-- routine cannot safely advertise itself as STABLE. Date/timestamp conversion
-- helpers are STABLE, not IMMUTABLE. Extension-owned digest() is untouched.
-- ---------------------------------------------------------------------------
do $$
declare
  v_name text;
  v_proc record;
  v_volatile constant text[]:=array[
    'erp_search_cloud_documents','erp_r22_cash_health',
    'erp_v2300_get_commercial_order_complete_details','erp_r9_cloud_cash_currency_summary',
    'erp_r9_cloud_trial_balance','erp_r9_cloud_account_balance_before',
    'erp_r9_cloud_detailed_accounting_report','erp_r9_cloud_cash_flow_hierarchy',
    'erp_r9_cloud_contextual_report','erp_r9_cloud_model_report',
    'erp_r9_cloud_customer_service_report','erp_r9_cloud_report_audit',
    'erp_r9_cloud_reports_summary','erp_r9_cloud_dashboard_snapshot',
    'erp_get_cloud_current_document_blob','erp_get_cloud_document',
    'erp_list_cloud_document_versions','erp_list_cloud_document_permissions',
    'erp_r15_current_state_health','erp_r49_get_sales_order_draft',
    'erp_r49_get_purchase_order_draft'
  ];
  v_stable constant text[]:=array['erp_try_date','erp_try_timestamptz'];
begin
  foreach v_name in array v_volatile loop
    for v_proc in
      select p.oid::regprocedure signature
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop execute format('alter function %s volatile',v_proc.signature); end loop;
  end loop;
  foreach v_name in array v_stable loop
    for v_proc in
      select p.oid::regprocedure signature
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop execute format('alter function %s stable',v_proc.signature); end loop;
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
