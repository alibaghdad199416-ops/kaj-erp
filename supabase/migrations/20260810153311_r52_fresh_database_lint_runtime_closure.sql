begin;

-- The accepted-module cleanup intentionally retired the legacy document
-- processing subsystem. Keep the system-monitor JSON contract, but report the
-- cloud-only architecture's real zero queue instead of querying or mutating a
-- table that no longer exists.
create or replace function public.erp_r9_system_monitor_command(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company uuid;
  v_slug text;
  v_admin boolean;
  v_result jsonb := '{}'::jsonb;
begin
  select company_uuid,company_slug,is_admin
    into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;
  if not v_admin and not public.erp_cloud_user_has_permission(v_company,'settings.view') then
    raise exception 'permission_denied:settings.view' using errcode='42501';
  end if;
  if not v_admin and not public.erp_cloud_user_can_view_field(
       v_company,'settings','systemMonitor','settings.view'
     ) then
    raise exception 'permission_denied:settings.systemMonitor' using errcode='42501';
  end if;

  if p_action='snapshot' then
    if v_admin or public.erp_cloud_user_can_view_field(v_company,'settings','systemMetrics','settings.view') then
      v_result := v_result || jsonb_build_object(
        'cloud_table_count',(select count(distinct entity_type) from public.erp_records where company_id=v_slug),
        'cloud_record_count',(select count(*) from public.erp_records where company_id=v_slug and deleted_at is null),
        'active_sessions',(select count(*) from public.company_memberships where company_id=v_company and is_active),
        'backup_count',(select count(*) from public.erp_cloud_backups where company_id=v_company and deleted_at is null),
        'audit_log_count',(select count(*) from public.erp_records where company_id=v_slug and entity_type='audit_logs' and deleted_at is null)
      );
    end if;
    if v_admin or public.erp_cloud_user_can_view_field(v_company,'settings','systemSyncDetails','settings.view') then
      v_result := v_result || jsonb_build_object(
        'pending_sync_operations',0,
        'failed_sync_operations',0,
        'oldest_pending_at',null,
        'last_backup_at',(select max(created_at) from public.erp_cloud_backups where company_id=v_company and deleted_at is null),
        'last_backup_status',(select status from public.erp_cloud_backups where company_id=v_company and deleted_at is null order by created_at desc limit 1)
      );
    end if;
    if v_admin or public.erp_cloud_user_can_view_field(v_company,'settings','systemHealth','settings.view') then
      v_result := v_result || jsonb_build_object('health','ok','server_time',clock_timestamp());
    end if;
    return v_result;
  elsif p_action='health_check' then
    if not v_admin
       and not public.erp_cloud_user_can_view_field(v_company,'settings','systemHealth','settings.view')
       and not public.erp_cloud_user_can_view_field(v_company,'settings','productionReadiness','settings.view') then
      raise exception 'permission_denied:settings.systemHealth' using errcode='42501';
    end if;
    return jsonb_build_object('healthy',true,'server_time',clock_timestamp());
  elsif p_action='retry_server_jobs' then
    if not v_admin and not public.erp_cloud_user_can_edit_field(
       v_company,'settings','retryFailedJobs','settings.view'
    ) then
      raise exception 'permission_denied:settings.retryFailedJobs' using errcode='42501';
    end if;
    return jsonb_build_object('retried_jobs',0);
  end if;
  raise exception 'unsupported_system_monitor_action:%',p_action;
end;
$$;

revoke all on function public.erp_r9_system_monitor_command(text,jsonb) from public,anon;
grant execute on function public.erp_r9_system_monitor_command(text,jsonb) to authenticated,service_role;

-- Preserve dynamic table selection after the allowlist/contract checks, but
-- materialize each row as a typed JSON value. This makes the no-row state
-- explicit and removes false unassigned-RECORD diagnostics without changing
-- the browser response shape.
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
  if v_rel is null then raise exception 'master_table_not_found:%',p_table using errcode='42P01'; end if;
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
    'select jsonb_build_object(''id'',id::text,''data'',case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,'
    ||'''version'',version,''updated_at'',updated_at) from public.%I r '
    ||'where company_id=$1 and not coalesce(is_deleted,false) '
    ||'and not public.erp_r15_pending_delete_exists($1,%L,r.id) order by updated_at desc',
    p_table,p_table
  ) using p_company_id loop
    return next public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row->'data')
      ||jsonb_build_object(
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
  if v_rel is null then raise exception 'master_table_not_found:%',p_table using errcode='42P01'; end if;
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
    'select jsonb_build_object(''id'',id::text,''data'',case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end,'
    ||'''version'',version,''updated_at'',updated_at) from public.%I '
    ||'where company_id=$1 and id=$2 and not coalesce(is_deleted,false)',p_table
  ) into v_row using p_company_id,p_record_id;
  if v_row is null then return null; end if;
  return public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row->'data')
    ||jsonb_build_object(
      'id',v_row->>'id',
      '_cloudVersion',v_row->'version',
      '_cloudUpdatedAt',v_row->'updated_at'
    );
end;
$$;

revoke all on function public.erp_r9_list_cloud_master_records(uuid,text) from public,anon;
revoke all on function public.erp_r9_get_cloud_master_record(uuid,text,text) from public,anon;
grant execute on function public.erp_r9_list_cloud_master_records(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_get_cloud_master_record(uuid,text,text) to authenticated,service_role;

-- These eight canonical tables are required by the repository contract. Use
-- explicit statements so static analysis validates the same runtime work
-- without trying to interpret a FOREACH value as a relation name.
create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
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

  update public.erp_cars r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1
  where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_cars',r.id);
  get diagnostics v_count=row_count; v_redeleted:=v_redeleted+v_count;
  update public.erp_car_images r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1
  where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_car_images',r.id);
  get diagnostics v_count=row_count; v_redeleted:=v_redeleted+v_count;
  update public.erp_customers r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1
  where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_customers',r.id);
  get diagnostics v_count=row_count; v_redeleted:=v_redeleted+v_count;
  update public.erp_suppliers r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1
  where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_suppliers',r.id);
  get diagnostics v_count=row_count; v_redeleted:=v_redeleted+v_count;
  update public.erp_warehouses r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1
  where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_warehouses',r.id);
  get diagnostics v_count=row_count; v_redeleted:=v_redeleted+v_count;
  update public.erp_inventory r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1
  where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_inventory',r.id);
  get diagnostics v_count=row_count; v_redeleted:=v_redeleted+v_count;
  update public.erp_inventory_groups r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1
  where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_inventory_groups',r.id);
  get diagnostics v_count=row_count; v_redeleted:=v_redeleted+v_count;
  update public.erp_product_images r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1
  where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_product_images',r.id);
  get diagnostics v_count=row_count; v_redeleted:=v_redeleted+v_count;

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

revoke all on function public.erp_r15_reconcile_company_state(uuid) from public,anon;
grant execute on function public.erp_r15_reconcile_company_state(uuid) to authenticated,service_role;

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb;
  v_open_issues bigint:=0;
  v_tombstone_conflicts bigint:=0;
  v_tombstones bigint:=0;
  v_issue_details jsonb:='[]'::jsonb;
begin
  if auth.uid() is not null and not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  v_base:=public.erp_r15_current_state_health(p_company_id);
  select count(*) into v_open_issues from public.erp_canonical_reconciliation_issues
  where company_id=p_company_id and resolved_at is null;
  select count(*) into v_tombstones from public.erp_canonical_deletion_tombstones
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

  select
    (select count(*) from public.erp_cars r join public.erp_canonical_deletion_tombstones t
      on t.company_id=r.company_id and t.source_table='erp_cars' and t.record_id=r.id
      where r.company_id=p_company_id and t.restored_at is null and not coalesce(r.is_deleted,false))
    +(select count(*) from public.erp_car_images r join public.erp_canonical_deletion_tombstones t
      on t.company_id=r.company_id and t.source_table='erp_car_images' and t.record_id=r.id
      where r.company_id=p_company_id and t.restored_at is null and not coalesce(r.is_deleted,false))
    +(select count(*) from public.erp_customers r join public.erp_canonical_deletion_tombstones t
      on t.company_id=r.company_id and t.source_table='erp_customers' and t.record_id=r.id
      where r.company_id=p_company_id and t.restored_at is null and not coalesce(r.is_deleted,false))
    +(select count(*) from public.erp_suppliers r join public.erp_canonical_deletion_tombstones t
      on t.company_id=r.company_id and t.source_table='erp_suppliers' and t.record_id=r.id
      where r.company_id=p_company_id and t.restored_at is null and not coalesce(r.is_deleted,false))
    +(select count(*) from public.erp_warehouses r join public.erp_canonical_deletion_tombstones t
      on t.company_id=r.company_id and t.source_table='erp_warehouses' and t.record_id=r.id
      where r.company_id=p_company_id and t.restored_at is null and not coalesce(r.is_deleted,false))
    +(select count(*) from public.erp_inventory r join public.erp_canonical_deletion_tombstones t
      on t.company_id=r.company_id and t.source_table='erp_inventory' and t.record_id=r.id
      where r.company_id=p_company_id and t.restored_at is null and not coalesce(r.is_deleted,false))
    +(select count(*) from public.erp_inventory_groups r join public.erp_canonical_deletion_tombstones t
      on t.company_id=r.company_id and t.source_table='erp_inventory_groups' and t.record_id=r.id
      where r.company_id=p_company_id and t.restored_at is null and not coalesce(r.is_deleted,false))
    +(select count(*) from public.erp_product_images r join public.erp_canonical_deletion_tombstones t
      on t.company_id=r.company_id and t.source_table='erp_product_images' and t.record_id=r.id
      where r.company_id=p_company_id and t.restored_at is null and not coalesce(r.is_deleted,false))
    into v_tombstone_conflicts;

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

revoke all on function public.erp_r16_current_state_health(uuid) from public,anon;
grant execute on function public.erp_r16_current_state_health(uuid) to authenticated,service_role;

-- erp_records has one authoritative database timestamp: updated_at. Payload
-- timestamps remain preferred for legacy records; updated_at is the final
-- fallback and keeps opportunity ordering deterministic.
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
    select
      case
        when b.row_payload->>'type'='القيود المحاسبية' then
          jsonb_set(
            b.row_payload,
            '{status}',
            to_jsonb(coalesce((
              select nullif(j.data->>'status','')
              from public.erp_journal_entries j
              where j.company_id=p_company_id
                and j.id::text=b.row_payload->>'id'
                and not j.is_deleted
              limit 1
            ),'unknown')),
            true
          )
        else b.row_payload
      end as row_payload,
      20 as rank
    from public.erp_r9_cloud_global_search(p_company_id,p_query,v_limit) as b(row_payload)
  ), enriched_base as (
    select
      case when public.erp_r49_search_result_currency(p_company_id,row_payload) is null
        then row_payload
        else row_payload || jsonb_build_object(
          'currency',public.erp_r49_search_result_currency(p_company_id,row_payload)
        )
      end as row_payload,
      rank
    from base
  ), opportunities as (
    select jsonb_build_object(
      'id',r.record_id,
      'type','الفرص التجارية',
      'title',coalesce(nullif(r.payload->>'title',''),nullif(r.payload->>'opportunityNumber',''),'فرصة تجارية'),
      'subtitle',concat_ws(' • ',
        nullif(r.payload->>'opportunityNumber',''),
        nullif(r.payload->>'customerName',''),
        nullif(r.payload->>'stage','')
      ),
      'route','/customer-service',
      'permission','customer_service.view',
      'icon','opportunity',
      'status',coalesce(nullif(r.payload->>'status',''),nullif(r.payload->>'stage',''),'pending'),
      'amount',public.erp_try_numeric(r.payload->>'expectedValue',0),
      'currency',case when upper(coalesce(r.payload->>'currency','')) in ('USD','IQD') then upper(r.payload->>'currency') else null end,
      'date',coalesce(nullif(r.payload->>'updatedAt',''),nullif(r.payload->>'createdAt',''),r.updated_at::text)
    ) as row_payload,
    10 as rank
    from public.erp_records r
    where r.company_id=v_slug
      and r.entity_type='opportunities'
      and r.deleted_at is null
      and (
        public.is_company_admin(p_company_id)
        or public.erp_cloud_user_has_permission(p_company_id,'customer_service.view')
      )
      and (
        coalesce(r.payload->>'opportunityNumber','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'title','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'customerName','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'customerPhone','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'stage','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'status','') ilike '%'||btrim(p_query)||'%'
      )
  )
  select x.row_payload
  from (
    select row_payload,rank from opportunities
    union all
    select row_payload,rank from enriched_base
  ) x
  order by x.rank,coalesce(x.row_payload->>'date','') desc
  limit v_limit;
end $$;

revoke all on function public.erp_r49_cloud_global_search(uuid,text,integer) from public,anon;
grant execute on function public.erp_r49_cloud_global_search(uuid,text,integer) to authenticated,service_role;

notify pgrst,'reload schema';

commit;
