begin;

-- Final runtime-contract cleanup. These helpers parse timezone-aware timestamps,
-- so they cannot truthfully be IMMUTABLE: the text -> timestamptz -> date path
-- depends on the session timezone.
alter function public.erp_try_date(text,date) stable;
alter function public.erp_try_timestamptz(text,timestamptz) stable;

-- Phase 2/3 JSON accumulators must be typed explicitly. This is intentionally a
-- compatibility migration; it does not alter posting semantics or historical data.
do $$
begin
  if to_regprocedure('public.erp_phase2_post_scrap(uuid,text,text,text,jsonb,text)') is not null then
    execute $fn$
      create or replace function public.erp_phase2_post_scrap(
        p_company_id uuid,p_warehouse_id text,p_reference_id text,p_currency text,
        p_items jsonb,p_notes text default null
      ) returns text language plpgsql security definer set search_path=public as $$
      declare
        w public.erp_warehouses%rowtype;
        i jsonb; ac jsonb; qty numeric; cost numeric; amount numeric;
        lines jsonb := '[]'::jsonb; expense text; eid text;
      begin
        if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
        select * into w from public.erp_warehouses
        where company_id=p_company_id and id=p_warehouse_id and not is_deleted for update;
        if not found then raise exception 'مخزن التوالف غير موجود'; end if;
        expense:=nullif(coalesce(w.data->>'scrapExpenseAccountId',w.data->>'scrap_expense_account_id'),'');
        perform public.erp_phase2_account_guard(p_company_id,expense,'expense',p_currency);
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
        eid:=public.erp_phase2_insert_journal(
          p_company_id,'inventory_scrap',p_reference_id,
          'SCRAP-'||replace(p_reference_id,'-',''),
          'قيد تلف واستهلاك '||coalesce(p_notes,''),p_currency,lines
        );
        return eid;
      end;
      $$;
    $fn$;
  end if;
end $$;

-- Dynamic master-table reads are deliberately VOLATILE. PL/pgSQL's checker
-- cannot prove the result shape of EXECUTE against a record variable; using a
-- JSON projection removes the indeterminate-record false positive and keeps the
-- runtime table selection fully parameterized.
create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,p_table text
) returns setof jsonb
language plpgsql volatile security definer set search_path=public as $$
declare
  v_permission text;
  v_rel regclass;
  v_row jsonb;
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

  for v_row in execute format(
    'select jsonb_build_object(''id'',id::text,''data'',case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,''version'',version,''updated_at'',updated_at) '
    ||'from public.%I where company_id=$1 and not coalesce(is_deleted,false) '
    ||'and not public.erp_r15_pending_delete_exists($1,$2,id) order by updated_at desc',
    p_table
  ) using p_company_id,p_table loop
    return next public.erp_r9_filter_readable_master_json(
      p_company_id,p_table,coalesce(v_row->'data','{}'::jsonb)
    ) || jsonb_build_object(
      'id',v_row->>'id',
      '_cloudVersion',v_row->'version',
      '_cloudUpdatedAt',v_row->'updated_at'
    );
  end loop;
  return;
end;
$$;

create or replace function public.erp_r9_get_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text
) returns jsonb
language plpgsql volatile security definer set search_path=public as $$
declare
  v_permission text;
  v_rel regclass;
  v_row jsonb;
  v_data jsonb;
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
    'select jsonb_build_object(''id'',id::text,''data'',case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,''version'',version,''updated_at'',updated_at) '
    ||'from public.%I where company_id=$1 and id=$2 and not coalesce(is_deleted,false)',
    p_table
  ) into v_row using p_company_id,p_record_id;
  if v_row is null then return null; end if;
  v_data:=coalesce(v_row->'data','{}'::jsonb);
  return public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_data)
    ||jsonb_build_object('id',v_row->>'id','_cloudVersion',v_row->'version','_cloudUpdatedAt',v_row->'updated_at');
end;
$$;

-- The reconciliation and health routines are rewritten with parameterized
-- identifiers. The previous versions accidentally interpolated the entire
-- table-name array as one quoted identifier, which is both a lint error and a
-- real runtime failure. No accounting totals are changed by this repair.
create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path=public as $$
declare
  v_table text;
  v_cash record;
  v_repaired bigint:=0;
  v_cashboxes bigint:=0;
  v_result jsonb;
begin
  if auth.uid() is not null and not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if auth.uid() is not null and not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;

  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'update public.%I r set is_deleted=true,deleted_at=coalesce(r.deleted_at,t.deleted_at),updated_at=now(),version=coalesce(r.version,0)+1 '
        ||'from public.erp_canonical_deletion_tombstones t '
        ||'where t.company_id=r.company_id and t.source_table=$1 and t.record_id=r.id '
        ||'and t.restored_at is null and not coalesce(r.is_deleted,false) and r.company_id=$2',
        v_table
      ) using v_table,p_company_id;
      get diagnostics v_repaired = row_count;
    end if;
  end loop;

  for v_cash in select id from public.erp_cash_accounts where company_id=p_company_id and not is_deleted loop
    perform public.erp_r15_rebind_cashbox_journals_internal(p_company_id,v_cash.id);
    v_cashboxes:=v_cashboxes+1;
  end loop;

  select public.erp_r15_current_state_health(p_company_id) into v_result;
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'reconciledAt',timezone('utc',now()),
    'repairedMasterRows',v_repaired,
    'cashboxesReconciled',v_cashboxes
  );
end;
$$;

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path=public as $$
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
  v_base:=coalesce(public.erp_r15_current_state_health(p_company_id),'{}'::jsonb);
  select count(*) into v_open_issues from public.erp_canonical_reconciliation_issues
    where company_id=p_company_id and resolved_at is null;
  select count(*) into v_tombstones from public.erp_canonical_deletion_tombstones
    where company_id=p_company_id and restored_at is null;
  select coalesce(jsonb_agg(q order by (q->>'last_seen_at') desc),'[]'::jsonb) into v_issue_details
  from (
    select jsonb_build_object(
      'issueType',issue_type,'entityType',entity_type,'entityId',entity_id,
      'details',details,'firstSeenAt',first_seen_at,'lastSeenAt',last_seen_at
    ) q
    from public.erp_canonical_reconciliation_issues
    where company_id=p_company_id and resolved_at is null
    order by last_seen_at desc limit 25
  ) s;

  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones t '
        ||'on t.company_id=r.company_id and t.source_table=$1 and t.record_id=r.id '
        ||'where r.company_id=$2 and t.restored_at is null and not coalesce(r.is_deleted,false)',
        v_table
      ) into v_count using v_table,p_company_id;
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

-- Keep the browser-facing R15/R16 health surfaces aligned with the repaired
-- implementations and remove accidental public execution paths.
revoke all on function public.erp_r15_reconcile_company_state(uuid) from public,anon;
revoke all on function public.erp_r16_current_state_health(uuid) from public,anon;
grant execute on function public.erp_r15_reconcile_company_state(uuid) to authenticated,service_role;
grant execute on function public.erp_r16_current_state_health(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
