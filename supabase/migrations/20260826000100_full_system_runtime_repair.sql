begin;

-- KAJ ERP 2026-08-26 runtime repair.
-- This migration repairs functions that may exist in an older local database
-- even when the checked-in migration source has already been corrected.
-- It is additive: no business data is deleted or rewritten by this migration.

-- ---------------------------------------------------------------------------
-- 1. Document-processing contract: the table is required by system monitoring.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_document_processing_jobs
  (like public.erp_contracts including all);

create index if not exists erp_doc_job_status_idx
  on public.erp_document_processing_jobs(company_id,((data->>'status')),created_at);
alter table public.erp_document_processing_jobs enable row level security;
drop policy if exists tenant_access on public.erp_document_processing_jobs;
create policy tenant_access on public.erp_document_processing_jobs
  for all using (erp_user_belongs_to_company(company_id))
  with check (erp_user_belongs_to_company(company_id));

-- ---------------------------------------------------------------------------
-- 2. R9 dynamic-master readers: do not use an untyped RECORD as the target of
--    EXECUTE. This removes the false-positive/real runtime hazard where the
--    record tuple has no determined structure.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,p_table text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_row jsonb;
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
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  for v_row in execute format(
    'select jsonb_build_object(''id'',id::text,''data'',case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,''version'',version,''updated_at'',updated_at) '
    ||'from public.%I r where company_id=$1 and not coalesce(is_deleted,false) '
    ||'and not public.erp_r15_pending_delete_exists($1,%L,r.id) order by updated_at desc',
    p_table,p_table
  ) using p_company_id loop
    return next public.erp_r9_filter_readable_master_json(
      p_company_id,p_table,coalesce(v_row->'data','{}'::jsonb)
    ) || jsonb_build_object(
      'id',v_row->>'id',
      '_cloudVersion',public.erp_try_bigint(v_row->>'version',0),
      '_cloudUpdatedAt',v_row->>'updated_at'
    );
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
  v_row jsonb;
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
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;
  if public.erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id) then
    return null;
  end if;
  execute format(
    'select jsonb_build_object(''id'',id::text,''data'',case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,''version'',version,''updated_at'',updated_at) '
    ||'from public.%I where company_id=$1 and id=$2 and not coalesce(is_deleted,false)',p_table
  ) into v_row using p_company_id,p_record_id;
  if v_row is null then return null; end if;
  return public.erp_r9_filter_readable_master_json(
    p_company_id,p_table,coalesce(v_row->'data','{}'::jsonb)
  ) || jsonb_build_object(
    'id',v_row->>'id',
    '_cloudVersion',public.erp_try_bigint(v_row->>'version',0),
    '_cloudUpdatedAt',v_row->>'updated_at'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. R15 reconciliation/health: replace the stale array-as-table SQL with the
--    already-designed per-table dynamic loop. No accounting amounts are changed.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r15_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  with resurrected_rows(table_name,id) as (
    select 'erp_cars',id from public.erp_cars where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_cars',id)
    union all select 'erp_car_images',id from public.erp_car_images where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_car_images',id)
    union all select 'erp_customers',id from public.erp_customers where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_customers',id)
    union all select 'erp_suppliers',id from public.erp_suppliers where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_suppliers',id)
    union all select 'erp_warehouses',id from public.erp_warehouses where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_warehouses',id)
    union all select 'erp_inventory',id from public.erp_inventory where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_inventory',id)
    union all select 'erp_inventory_groups',id from public.erp_inventory_groups where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_inventory_groups',id)
    union all select 'erp_product_images',id from public.erp_product_images where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_product_images',id)
  ), resurrected as (
    select count(*)::bigint n from resurrected_rows
  ), resurrected_warehouses as (
    select count(*)::bigint n from resurrected_rows where table_name='erp_warehouses'
  ), cap_accounts as (
    select count(*)::bigint n from public.erp_accounts a
    where a.organization_id=p_company_id and a.is_active
      and public.erp_v763_forbidden_capitalization_account(a.code,a.name)
  ), cap_lines as (
    select count(*)::bigint n
    from public.erp_journal_lines jl
    join public.erp_accounts a on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
    join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
    where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus','')) in ('posted','approved','confirmed')
      and public.erp_v763_forbidden_capitalization_account(a.code,a.name)
  ), cap_invoices as (
    select count(*)::bigint n from public.erp_r15_legacy_capitalized_purchase_invoices(p_company_id)
  ), cash_diff as (
    select count(*)::bigint n from public.erp_cloud_cash_ledger_reconciliation(p_company_id)
    where abs(difference)>0.01
  ), cash_binding_issues as (
    select count(*)::bigint n
    from public.erp_cash_transactions ct
    join public.erp_cash_accounts ca
      on ca.company_id=ct.company_id and ca.id=coalesce(ct.data->>'cashAccountId',ct.data->>'cash_account_id')
      and not ca.is_deleted
    left join lateral (
      select count(*)::integer n
      from public.erp_journal_lines jl
      join public.erp_journal_entries je
        on je.company_id=jl.company_id and je.id=jl.data->>'entryId' and not je.is_deleted
      where jl.company_id=ct.company_id and not jl.is_deleted
        and jl.data->>'entryId'=coalesce(ct.data->>'journalEntryId',ct.data->>'journal_entry_id')
        and jl.data->>'accountId'=coalesce(ca.data->>'accountId',ca.data->>'account_id')
        and upper(coalesce(nullif(jl.data->>'currency',''),je.data->>'currency',''))=
            upper(coalesce(ct.data->>'currency',''))
        and (
          (lower(coalesce(ct.data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
            and abs(public.erp_try_numeric(jl.data->>'debit',0)-abs(public.erp_try_numeric(ct.data->>'amount',0)))<=0.01
            and abs(public.erp_try_numeric(jl.data->>'credit',0))<=0.01)
          or
          (lower(coalesce(ct.data->>'type','')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out')
            and abs(public.erp_try_numeric(jl.data->>'credit',0)-abs(public.erp_try_numeric(ct.data->>'amount',0)))<=0.01
            and abs(public.erp_try_numeric(jl.data->>'debit',0))<=0.01)
        )
    ) match on true
    where ct.company_id=p_company_id and not ct.is_deleted
      and nullif(coalesce(ct.data->>'journalEntryId',ct.data->>'journal_entry_id'),'') is not null
      and coalesce(match.n,0)<>1
  )
  select jsonb_build_object(
    'ok',(select n=0 from resurrected) and (select n=0 from cap_accounts)
      and (select n=0 from cap_lines) and (select n=0 from cash_diff)
      and (select n=0 from cash_binding_issues),
    'resurrectedMasterCount',(select n from resurrected),
    'resurrectedWarehouseCount',(select n from resurrected_warehouses),
    'activeLegacyCapitalizationAccountCount',(select n from cap_accounts),
    'historicalCapitalizationLineCount',(select n from cap_lines),
    'legacyCapitalizedPurchaseInvoiceCount',(select n from cap_invoices),
    'cashboxLedgerMismatchCount',(select n from cash_diff),
    'cashJournalBindingIssueCount',(select n from cash_binding_issues),
    'checkedAt',timezone('utc',now())
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_table text;
  v_cash record;
  v_invoice uuid;
  v_redeleted integer:=0;
  v_count integer;
  v_cash_results jsonb:='[]'::jsonb;
  v_invoice_results jsonb:='[]'::jsonb;
  v_invoice_failures jsonb:='[]'::jsonb;
  v_normalized integer:=0;
  v_failed integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'update public.%I r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1 '
        ||'where company_id=$1 and not is_deleted and public.erp_r15_pending_delete_exists($1,%L,r.id)',v_table,v_table
      ) using p_company_id;
      get diagnostics v_count=row_count;
      v_redeleted:=v_redeleted+v_count;
    end if;
  end loop;

  update public.erp_accounts
  set is_active=false,name='حساب تاريخي متوقف - رسملة ملغاة',source_updated_at=now(),synced_at=now()
  where organization_id=p_company_id and public.erp_v763_forbidden_capitalization_account(code,name);

  for v_invoice in select * from public.erp_r15_legacy_capitalized_purchase_invoices(p_company_id) loop
    begin
      v_result:=public.erp_r15_normalize_legacy_purchase_invoice(p_company_id,v_invoice);
      v_invoice_results:=v_invoice_results||jsonb_build_array(v_result);
      v_normalized:=v_normalized+1;
    exception when others then
      v_failed:=v_failed+1;
      v_invoice_failures:=v_invoice_failures||jsonb_build_array(jsonb_build_object(
        'invoiceId',v_invoice,'sqlstate',sqlstate,'error',sqlerrm));
    end;
  end loop;

  for v_cash in select id from public.erp_cash_accounts where company_id=p_company_id and not is_deleted loop
    v_cash_results:=v_cash_results||jsonb_build_array(
      public.erp_r15_rebind_cashbox_journals_internal(p_company_id,v_cash.id));
  end loop;

  return jsonb_build_object('ok',v_failed=0,'redeletedStaleRows',v_redeleted,
    'normalizedLegacyPurchaseInvoices',v_normalized,'failedLegacyPurchaseInvoices',v_failed,
    'invoiceResults',v_invoice_results,'invoiceFailures',v_invoice_failures,
    'cashboxes',v_cash_results,'health',public.erp_r15_current_state_health(p_company_id));
end;
$$;

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb;
  v_open_issues bigint:=0;
  v_tombstone_conflicts bigint:=0;
  v_tombstones bigint:=0;
  v_issue_details jsonb:='[]'::jsonb;
  v_table text;
  v_count bigint;
begin
  if auth.uid() is not null and not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  v_base:=public.erp_r15_current_state_health(p_company_id);
  select count(*) into v_open_issues
  from public.erp_canonical_reconciliation_issues
  where company_id=p_company_id and resolved_at is null;
  select count(*) into v_tombstones
  from public.erp_canonical_deletion_tombstones
  where company_id=p_company_id and restored_at is null;
  select coalesce(jsonb_agg(jsonb_build_object(
      'issueType',q.issue_type,'entityType',q.entity_type,'entityId',q.entity_id,
      'details',q.details,'firstSeenAt',q.first_seen_at,'lastSeenAt',q.last_seen_at
    ) order by q.last_seen_at desc),'[]'::jsonb) into v_issue_details
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
        ||'on t.company_id=r.company_id and t.source_table=%L and t.record_id=r.id '
        ||'where r.company_id=$1 and t.restored_at is null and not coalesce(r.is_deleted,false)',
        v_table,v_table
      ) into v_count using p_company_id;
      v_tombstone_conflicts:=v_tombstone_conflicts+coalesce(v_count,0);
    end if;
  end loop;
  return v_base||jsonb_build_object(
    'ok',coalesce((v_base->>'ok')::boolean,false) and v_open_issues=0 and v_tombstone_conflicts=0,
    'persistentDeletionConflictCount',v_tombstone_conflicts,
    'permanentDeletionTombstoneCount',v_tombstones,
    'unresolvedCanonicalReconciliationIssueCount',v_open_issues,
    'openCanonicalIssues',v_issue_details,
    'canonicalStateVersion',16,
    'checkedAt',timezone('utc',now())
  );
end;
$$;

create or replace function public.erp_r16_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;
  v_result:=public.erp_r15_reconcile_company_state(p_company_id);
  return v_result||jsonb_build_object('canonicalStateVersion',16,'health',public.erp_r16_current_state_health(p_company_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Phase-2 scrap posting: force the JSONB accumulator type explicitly.
-- ---------------------------------------------------------------------------
create or replace function public.erp_phase2_post_scrap(
 p_company_id uuid,p_warehouse_id text,p_reference_id text,p_currency text,p_items jsonb,p_notes text default null
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
 select * into w from public.erp_warehouses where company_id=p_company_id and id=p_warehouse_id and not is_deleted for update;
 if not found then raise exception 'مخزن التوالف غير موجود'; end if;
 expense:=nullif(coalesce(w.data->>'scrapExpenseAccountId',w.data->>'scrap_expense_account_id'),'');
 perform public.erp_phase2_account_guard(p_company_id,expense,'expense',p_currency);
 for i in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
   qty:=public.erp_try_numeric(i->>'quantity',0); if qty<=0 then raise exception 'كمية التلف غير صحيحة'; end if;
   ac:=public.erp_phase2_item_accounts(p_company_id,coalesce(i->>'itemType','product'),i->>'itemId',p_currency);
   if coalesce(i->>'itemType','product')='car' then
     select public.erp_try_numeric(data->>'purchasePrice',0) into cost from public.erp_cars where company_id=p_company_id and id=i->>'itemId';
   else
     select public.erp_try_numeric(data->>'averageUnitCost',data->>'purchasePrice') into cost from public.erp_inventory where company_id=p_company_id and id=i->>'itemId';
   end if;
   amount:=qty*coalesce(cost,0);
   lines:=lines||jsonb_build_array(
    jsonb_build_object('accountId',expense,'debit',amount,'credit',0,'description','تالف/استهلاك '||coalesce(i->>'description',i->>'itemId')),
    jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',amount,'description','إخراج أصل مخزني'));
 end loop;
 eid:=public.erp_phase2_insert_journal(p_company_id,'inventory_scrap',p_reference_id,'SCRAP-'||replace(p_reference_id,'-',''),'قيد تلف واستهلاك '||coalesce(p_notes,''),p_currency,lines);
 return eid;
end $$;

-- ---------------------------------------------------------------------------
-- 5. R49 global search: erp_records has updated_at, not created_at.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r49_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
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
      jsonb_set(b.row_payload,'{status}',to_jsonb(coalesce((select nullif(j.data->>'status','')
        from public.erp_journal_entries j where j.company_id=p_company_id and j.id::text=b.row_payload->>'id' and not j.is_deleted limit 1),'unknown')),true)
      else b.row_payload end as row_payload,20 as rank
    from public.erp_r9_cloud_global_search(p_company_id,p_query,v_limit) as b(row_payload)
  ), enriched_base as (
    select case when public.erp_r49_search_result_currency(p_company_id,row_payload) is null then row_payload
      else row_payload||jsonb_build_object('currency',public.erp_r49_search_result_currency(p_company_id,row_payload)) end as row_payload,rank
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
    ) as row_payload,10 as rank
    from public.erp_records r
    where r.company_id=v_slug and r.entity_type='opportunities' and r.deleted_at is null
      and (public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'customer_service.view'))
      and (coalesce(r.payload->>'opportunityNumber','') ilike '%'||btrim(p_query)||'%' or
           coalesce(r.payload->>'title','') ilike '%'||btrim(p_query)||'%' or
           coalesce(r.payload->>'customerName','') ilike '%'||btrim(p_query)||'%' or
           coalesce(r.payload->>'customerPhone','') ilike '%'||btrim(p_query)||'%' or
           coalesce(r.payload->>'stage','') ilike '%'||btrim(p_query)||'%' or
           coalesce(r.payload->>'status','') ilike '%'||btrim(p_query)||'%')
  )
  select x.row_payload from (
    select row_payload,rank from opportunities union all select row_payload,rank from enriched_base
  ) x
  order by x.rank,coalesce(x.row_payload->>'date','') desc limit v_limit;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Volatility correctness. These routines are read facades over table state
--    or call volatile routines, so STABLE/IMMUTABLE was an invalid promise.
--    The change only affects planner semantics; it does not change accounting.
-- ---------------------------------------------------------------------------
do $$
declare
  n text;
  names text[]:=array[
    'erp_try_date','erp_try_timestamptz','digest',
    'erp_search_cloud_documents','erp_r22_cash_health','erp_v2300_get_commercial_order_complete_details',
    'erp_r9_cloud_cash_currency_summary','erp_r9_cloud_trial_balance','erp_r9_cloud_account_balance_before',
    'erp_r9_cloud_detailed_accounting_report','erp_r9_cloud_cash_flow_hierarchy','erp_r9_cloud_contextual_report',
    'erp_r9_cloud_model_report','erp_r9_cloud_customer_service_report','erp_r9_cloud_report_audit',
    'erp_r9_cloud_reports_summary','erp_r9_cloud_dashboard_snapshot','erp_get_cloud_current_document_blob',
    'erp_get_cloud_document','erp_list_cloud_document_versions','erp_list_cloud_document_permissions',
    'erp_r49_get_sales_order_draft','erp_r49_get_purchase_order_draft','erp_r49_search_result_currency',
    'erp_r49_cloud_global_search'
  ];
begin
  foreach n in array names loop
    for r in select p.oid::regprocedure::text as signature
      from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.proname=n and p.prokind='f' and p.provolatile in ('i','s')
    loop
      execute format('alter function %s volatile',r.signature);
    end loop;
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
