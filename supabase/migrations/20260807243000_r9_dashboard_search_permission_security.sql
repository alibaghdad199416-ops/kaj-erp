begin;

-- R9 security boundary for executive dashboard data. Field-restricted users
-- receive only explicitly granted top-level dashboard properties; unrestricted
-- users retain the existing dashboard payload byte-for-byte.
create or replace function public.erp_r9_cloud_dashboard_snapshot(
  p_company_id uuid,
  p_reference_day date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_raw jsonb;
  v_result jsonb := '{}'::jsonb;
  v_item record;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.view')
     and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:dashboard.view' using errcode='42501';
  end if;

  v_raw := public.erp_cloud_dashboard_snapshot(p_company_id,p_reference_day);
  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.fields.restrict') then
    return v_raw;
  end if;

  for v_item in select key,value from jsonb_each(coalesce(v_raw,'{}'::jsonb)) loop
    if public.erp_cloud_user_can_view_field(
         p_company_id,'dashboard',v_item.key,'dashboard.view'
       ) then
      v_result := v_result || jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

revoke all on function public.erp_r9_cloud_dashboard_snapshot(uuid,date) from public,anon;
grant execute on function public.erp_r9_cloud_dashboard_snapshot(uuid,date) to authenticated,service_role;

-- The legacy search function returns a permission code with every result, but
-- older Flutter filtered it only after the rows reached the browser. R9 moves
-- that authorization decision to PostgreSQL so unauthorized module results do
-- not leave Supabase at all.
create or replace function public.erp_r9_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language sql
stable
security definer
set search_path=public
as $$
  select row_payload
  from public.erp_cloud_global_search(
    p_company_id,
    p_query,
    greatest(1,least(coalesce(p_limit,50),200))
  ) as row_payload
  where public.is_active_company_member(p_company_id)
    and (
      public.is_company_admin(p_company_id)
      or public.erp_cloud_user_has_permission(
        p_company_id,
        coalesce(row_payload->>'permission','')
      )
    );
$$;

revoke all on function public.erp_r9_cloud_global_search(uuid,text,integer) from public,anon;
grant execute on function public.erp_r9_cloud_global_search(uuid,text,integer) to authenticated,service_role;



-- System-monitor data is field-filtered at the server boundary. The legacy
-- phase-26 endpoint exposed company aggregates to any company member and its
-- retry action was a no-op; R9 makes both permission-aware and real.
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
  v_retried integer := 0;
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
        'pending_sync_operations',(select count(*) from public.erp_document_processing_jobs where company_id=v_company and not is_deleted and coalesce(data->>'status','')='pending'),
        'failed_sync_operations',(select count(*) from public.erp_document_processing_jobs where company_id=v_company and not is_deleted and coalesce(data->>'status','')='failed'),
        'oldest_pending_at',(select min(created_at) from public.erp_document_processing_jobs where company_id=v_company and not is_deleted and coalesce(data->>'status','')='pending'),
        'last_backup_at',(select max(created_at) from public.erp_cloud_backups where company_id=v_company and deleted_at is null),
        'last_backup_status',(select status from public.erp_cloud_backups where company_id=v_company and deleted_at is null order by created_at desc limit 1)
      );
    end if;
    if v_admin or public.erp_cloud_user_can_view_field(v_company,'settings','systemHealth','settings.view') then
      v_result := v_result || jsonb_build_object(
        'health','ok',
        'server_time',clock_timestamp()
      );
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
    update public.erp_document_processing_jobs
       set data=data || jsonb_build_object(
             'status','pending','errorMessage','',
             'retriedAt',clock_timestamp(),'retriedBy',auth.uid()
           ),
           updated_at=clock_timestamp()
     where company_id=v_company
       and not is_deleted
       and coalesce(data->>'status','')='failed';
    get diagnostics v_retried = row_count;
    return jsonb_build_object('retried_jobs',v_retried);
  end if;
  raise exception 'unsupported_system_monitor_action:%',p_action;
end;
$$;

revoke all on function public.erp_r9_system_monitor_command(text,jsonb) from public,anon;
grant execute on function public.erp_r9_system_monitor_command(text,jsonb) to authenticated,service_role;

-- Permission-aware facade for the remaining legacy Phase-26 JSON command.
-- Direct authenticated execution of the legacy function is revoked below, so
-- field-restricted users cannot bypass Flutter by calling it themselves.
create or replace function public.erp_r9_phase26_cloud_command(
  p_area text,
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
  v_raw jsonb;
  v_result jsonb;
  v_payload jsonb := coalesce(p_payload,'{}'::jsonb);
  v_record jsonb;
  v_existing jsonb := '{}'::jsonb;
  v_id text;
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;

  if p_area='system_monitor' then
    return public.erp_r9_system_monitor_command(p_action,v_payload);
  end if;

  if p_area='backup' then
    if not v_admin and not public.erp_cloud_user_has_permission(v_company,'settings.view') then
      raise exception 'permission_denied:settings.view' using errcode='42501';
    end if;
    if p_action in ('list','export','verify','create','delete') then
      if not v_admin and not public.erp_cloud_user_can_view_field(v_company,'settings','backup','settings.view') then
        raise exception 'permission_denied:settings.backup' using errcode='42501';
      end if;
      if p_action in ('export','verify','create','delete')
         and not v_admin
         and (
           not public.erp_cloud_user_has_permission(v_company,'settings.backup')
           or not public.erp_cloud_user_can_edit_field(v_company,'settings','backup','settings.view')
         ) then
        raise exception 'permission_denied:settings.backup.manage' using errcode='42501';
      end if;
    elsif p_action in ('import','restore') then
      if not v_admin
         and (
           not public.erp_cloud_user_has_permission(v_company,'settings.restore')
           or not public.erp_cloud_user_can_edit_field(v_company,'settings','restore','settings.view')
         ) then
        raise exception 'permission_denied:settings.restore' using errcode='42501';
      end if;
    end if;
    return public.erp_phase26_cloud_command(p_area,p_action,v_payload);
  end if;

  if p_area='opportunity' then
    if p_action='list' then
      if not v_admin and not public.erp_cloud_user_has_permission(v_company,'customer_service.view') then
        raise exception 'permission_denied:customer_service.view' using errcode='42501';
      end if;
      v_raw := public.erp_phase26_cloud_command(p_area,p_action,v_payload);
      select coalesce(jsonb_agg(public.erp_r9_filter_readable_json(
               v_company,'opportunities',item
             )),'[]'::jsonb)
        into v_result
      from jsonb_array_elements(coalesce(v_raw,'[]'::jsonb)) item;
      return v_result;
    end if;

    if not v_admin and not public.erp_cloud_user_has_permission(v_company,'customer_service.create') then
      raise exception 'permission_denied:customer_service.create' using errcode='42501';
    end if;

    if p_action='save' then
      v_record := coalesce(v_payload->'record','{}'::jsonb);
      v_id := coalesce(nullif(v_record->>'id',''),gen_random_uuid()::text);
      select coalesce(payload,'{}'::jsonb) into v_existing
      from public.erp_records
      where company_id=v_slug and entity_type='opportunities'
        and record_id=v_id and deleted_at is null
      limit 1;
      v_existing := coalesce(v_existing,'{}'::jsonb);
      v_record := public.erp_r9_guard_writable_json(
        v_company,'opportunities',v_existing,v_record
      );
      -- Server owns immutable audit/identity metadata even when those fields are
      -- hidden from the operator.
      v_record := v_record || jsonb_build_object(
        'id',v_id,
        'opportunityNumber',coalesce(
          nullif(v_existing->>'opportunityNumber',''),
          'OPP-'||floor(extract(epoch from clock_timestamp())*1000)::bigint::text
        ),
        'createdAt',coalesce(v_existing->'createdAt',to_jsonb(clock_timestamp())),
        'updatedAt',to_jsonb(clock_timestamp())
      );
      if v_existing='{}'::jsonb then
        v_record := v_record || jsonb_build_object('status','pending');
      end if;
      v_payload := jsonb_set(v_payload,'{record}',v_record,true);
      return public.erp_phase26_cloud_command(p_area,p_action,v_payload);
    elsif p_action='mark_lost' then
      if not v_admin and not public.erp_cloud_user_can_edit_field(v_company,'opportunities','status','customer_service.create') then
        raise exception 'permission_denied:opportunities.status' using errcode='42501';
      end if;
      return public.erp_phase26_cloud_command(p_area,p_action,v_payload);
    elsif p_action='mark_won' then
      if not v_admin and (
         not public.erp_cloud_user_can_edit_field(v_company,'opportunities','status','customer_service.create')
         or not public.erp_cloud_user_can_edit_field(v_company,'opportunities','linkedSale','customer_service.create')
         or not public.erp_cloud_user_has_permission(v_company,'sales.create')
      ) then
        raise exception 'permission_denied:opportunities.convert' using errcode='42501';
      end if;
      v_raw := public.erp_phase26_cloud_command(p_area,p_action,v_payload);
      return public.erp_r9_filter_readable_json(v_company,'sales',v_raw);
    elsif p_action='delete' then
      return public.erp_phase26_cloud_command(p_area,p_action,v_payload);
    end if;
  end if;

  -- Company branding is needed by authorized PDF exports across commercial
  -- modules; the legacy function already enforces company membership.
  if p_area='company_settings' and p_action='branding' then
    return public.erp_phase26_cloud_command(p_area,p_action,v_payload);
  end if;

  raise exception 'unsupported_r9_phase26_command: %.%',p_area,p_action;
end;
$$;

revoke all on function public.erp_r9_phase26_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r9_phase26_cloud_command(text,text,jsonb) to authenticated,service_role;
-- The original entry point may now be called only from security-definer server
-- code, never directly by an authenticated browser session.
revoke execute on function public.erp_phase26_cloud_command(text,text,jsonb) from authenticated;



-- Granular settings writes: legacy mode remains administrator-only. Once
-- settings.fields.restrict is explicitly enabled, a non-admin may update only
-- the settings group whose `.edit` permission was granted.
create or replace function public.erp_r9_can_edit_settings_field(
  p_company_id uuid,
  p_field text
) returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select public.is_company_admin(p_company_id)
      or (
        public.erp_cloud_user_has_permission(p_company_id,'settings.fields.restrict')
        and public.erp_cloud_user_can_edit_field(
          p_company_id,'settings',p_field,'settings.view'
        )
      )
$$;
revoke all on function public.erp_r9_can_edit_settings_field(uuid,text) from public,anon;
grant execute on function public.erp_r9_can_edit_settings_field(uuid,text) to authenticated,service_role;

create or replace function public.erp_save_cloud_company_settings(p_settings jsonb)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company uuid;
  v_slug text;
  v_current jsonb;
  v_next jsonb;
  v_any boolean := false;
begin
  select company_uuid,company_slug into v_company,v_slug
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;
  if not public.is_company_admin(v_company)
     and not public.erp_cloud_user_has_permission(v_company,'settings.view') then
    raise exception 'permission_denied:settings.view' using errcode='42501';
  end if;

  select payload into v_current
  from public.erp_records
  where company_id=v_slug and entity_type='app_settings'
    and record_id='company' and deleted_at is null
  limit 1;
  v_current := coalesce(v_current,jsonb_build_object(
    'company_name','شركة خط الجودة','company_name_en','Quality Line',
    'company_phone','','company_email','','company_address','',
    'company_tax_number','','default_currency','USD','app_language','ar'
  ));
  v_next := v_current;

  if public.erp_r9_can_edit_settings_field(v_company,'companyProfile') then
    v_any := true;
    v_next := v_next || jsonb_build_object(
      'company_name',coalesce(p_settings->'company_name',v_current->'company_name'),
      'company_name_en',coalesce(p_settings->'company_name_en',v_current->'company_name_en'),
      'company_phone',coalesce(p_settings->'company_phone',v_current->'company_phone'),
      'company_email',coalesce(p_settings->'company_email',v_current->'company_email'),
      'company_address',coalesce(p_settings->'company_address',v_current->'company_address'),
      'company_tax_number',coalesce(p_settings->'company_tax_number',v_current->'company_tax_number')
    );
  end if;
  if public.erp_r9_can_edit_settings_field(v_company,'financialDefaults') then
    v_any := true;
    v_next := v_next || jsonb_build_object(
      'default_currency',coalesce(p_settings->'default_currency',v_current->'default_currency')
    );
  end if;
  if public.erp_r9_can_edit_settings_field(v_company,'language') then
    v_any := true;
    v_next := v_next || jsonb_build_object(
      'app_language',coalesce(p_settings->'app_language',v_current->'app_language')
    );
  end if;
  if not v_any then
    raise exception 'permission_denied:settings.fields.edit' using errcode='42501';
  end if;
  if coalesce(btrim(v_next->>'company_name'),'')='' then
    raise exception 'company_name_required';
  end if;

  insert into public.erp_records(
    company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
  ) values(v_slug,'app_settings','company',v_next,false,null,clock_timestamp())
  on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=clock_timestamp();
end;
$$;
revoke all on function public.erp_save_cloud_company_settings(jsonb) from public,anon;
grant execute on function public.erp_save_cloud_company_settings(jsonb) to authenticated,service_role;

create or replace function public.erp_save_cloud_branch(
  p_id text,p_name text,p_code text,p_phone text,p_address text,
  p_is_main boolean,p_is_active boolean,p_created_at timestamptz,p_updated_at timestamptz
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_company uuid; v_id uuid;
begin
  select company_uuid into v_company from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;
  if not public.erp_r9_can_edit_settings_field(v_company,'branches') then
    raise exception 'permission_denied:settings.branches' using errcode='42501';
  end if;
  v_id := p_id::uuid;
  if coalesce(btrim(p_name),'')='' or coalesce(btrim(p_code),'')='' then
    raise exception 'branch_name_code_required';
  end if;
  if p_is_main then
    update public.branches set is_main=false,updated_at=clock_timestamp()
    where company_id=v_company and id<>v_id;
  end if;
  insert into public.branches(
    id,company_id,code,name_ar,name_en,phone,address,is_main,is_active,created_at,updated_at
  ) values(
    v_id,v_company,btrim(p_code),btrim(p_name),btrim(p_name),
    nullif(btrim(p_phone),''),nullif(btrim(p_address),''),p_is_main,p_is_active,
    coalesce(p_created_at,clock_timestamp()),coalesce(p_updated_at,clock_timestamp())
  )
  on conflict(id) do update set
    code=excluded.code,name_ar=excluded.name_ar,name_en=excluded.name_en,
    phone=excluded.phone,address=excluded.address,is_main=excluded.is_main,
    is_active=excluded.is_active,updated_at=clock_timestamp()
  where branches.company_id=v_company;
end;
$$;

create or replace function public.erp_delete_cloud_branch(p_id text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_company uuid; v_main boolean;
begin
  select company_uuid into v_company from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;
  if not public.erp_r9_can_edit_settings_field(v_company,'branches') then
    raise exception 'permission_denied:settings.branches' using errcode='42501';
  end if;
  select is_main into v_main from public.branches where id=p_id::uuid and company_id=v_company;
  if v_main is null then raise exception 'branch_not_found'; end if;
  if v_main then raise exception 'cannot_delete_main_branch'; end if;
  delete from public.branches where id=p_id::uuid and company_id=v_company;
end;
$$;

create or replace function public.erp_save_cloud_currency(
  p_code text,p_name text,p_symbol text,p_exchange_rate numeric,
  p_is_base boolean,p_is_active boolean
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_company uuid; v_slug text; v_code text; v_payload jsonb;
begin
  select company_uuid,company_slug into v_company,v_slug
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;
  if not public.erp_r9_can_edit_settings_field(v_company,'currencies') then
    raise exception 'permission_denied:settings.currencies' using errcode='42501';
  end if;
  v_code := upper(btrim(p_code));
  if v_code='' then raise exception 'currency_code_required'; end if;
  if p_exchange_rate is null or p_exchange_rate<=0 then raise exception 'invalid_exchange_rate'; end if;
  if p_is_base then
    update public.erp_records
       set payload=jsonb_set(payload,'{isBase}','false'::jsonb,true),updated_at=clock_timestamp()
     where company_id=v_slug and entity_type='currencies' and deleted_at is null;
  end if;
  v_payload := jsonb_build_object(
    'code',v_code,'name',btrim(p_name),'symbol',btrim(p_symbol),
    'exchangeRate',p_exchange_rate,'isBase',p_is_base,'isActive',p_is_active
  );
  insert into public.erp_records(
    company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
  ) values(v_slug,'currencies',v_code,v_payload,false,null,clock_timestamp())
  on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=clock_timestamp();
end;
$$;

create or replace function public.erp_delete_cloud_currency(p_code text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_company uuid; v_slug text; v_base boolean;
begin
  select company_uuid,company_slug into v_company,v_slug
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;
  if not public.erp_r9_can_edit_settings_field(v_company,'currencies') then
    raise exception 'permission_denied:settings.currencies' using errcode='42501';
  end if;
  select coalesce((payload->>'isBase')::boolean,false) into v_base
  from public.erp_records
  where company_id=v_slug and entity_type='currencies'
    and record_id=upper(btrim(p_code)) and deleted_at is null;
  if v_base is null then raise exception 'currency_not_found'; end if;
  if v_base then raise exception 'cannot_delete_base_currency'; end if;
  update public.erp_records set is_deleted=true,deleted_at=clock_timestamp(),updated_at=clock_timestamp()
  where company_id=v_slug and entity_type='currencies'
    and record_id=upper(btrim(p_code)) and deleted_at is null;
end;
$$;

revoke all on function public.erp_save_cloud_branch(text,text,text,text,text,boolean,boolean,timestamptz,timestamptz) from public,anon;
revoke all on function public.erp_delete_cloud_branch(text) from public,anon;
revoke all on function public.erp_save_cloud_currency(text,text,text,numeric,boolean,boolean) from public,anon;
revoke all on function public.erp_delete_cloud_currency(text) from public,anon;
grant execute on function public.erp_save_cloud_branch(text,text,text,text,text,boolean,boolean,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_branch(text) to authenticated,service_role;
grant execute on function public.erp_save_cloud_currency(text,text,text,numeric,boolean,boolean) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_currency(text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
