-- Quality Line ERP R85
-- Completes per-user record scope across secondary read surfaces. Quick Search,
-- report detail sections, reservations, service cases and partner activities may
-- not bypass records.own through SECURITY DEFINER functions.
begin;

-- ---------------------------------------------------------------------------
-- 1. Customer-service tables share customer_service.records.own/all.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r85_customer_service_scope_guard()
returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if tg_op='INSERT' then
    if new.created_by is null then new.created_by:=auth.uid(); end if;
    return new;
  end if;
  if not public.erp_r84_record_visible(
    old.company_id,'customer_service',old.created_by,null
  ) then
    raise exception 'record_scope_denied:customer_service.records.own'
      using errcode='42501';
  end if;
  if tg_op='UPDATE' then
    new.created_by:=old.created_by;
    return new;
  end if;
  return old;
end;
$$;

forbidden_label: do $$
declare v_table text;
begin
  foreach v_table in array array['erp_service_cases','erp_partner_activities'] loop
    if to_regclass('public.'||v_table) is not null then
      execute format('drop trigger if exists aa_r85_customer_service_scope on public.%I',v_table);
      execute format(
        'create trigger aa_r85_customer_service_scope before insert or update or delete on public.%I '
        ||'for each row execute function public.erp_r85_customer_service_scope_guard()',v_table
      );
      execute format('drop policy if exists %I on public.%I',left(v_table||'_r85_record_scope',63),v_table);
      execute format(
        'create policy %I on public.%I as restrictive for select to authenticated using ('
        ||'public.is_active_company_member(company_id) '
        ||'and public.erp_r84_record_visible(company_id,''customer_service'',created_by,null))',
        left(v_table||'_r85_record_scope',63),v_table
      );
    end if;
  end loop;
end $$;

create or replace function public.erp_list_cloud_reservations(
  p_company_id uuid,p_query text default null
) returns table(
  "id" text,"reservationNumber" text,"carId" text,"carName" text,
  "customerId" text,"customerName" text,"customerPhone" text,
  "depositAmount" numeric,"startDate" text,"endDate" text,"status" text,
  "notes" text,"createdAt" text,"updatedAt" text
)
language sql stable security definer set search_path=public as $$
  select r.id::text,r.reservation_number,r.car_id::text,r.car_name,
         r.customer_id::text,r.customer_name,r.customer_phone,r.deposit_amount,
         r.start_date::text,r.end_date::text,r.status,r.notes,
         r.created_at::text,r.updated_at::text
  from public.erp_reservations r
  where r.company_id=p_company_id and not r.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_r84_record_visible(
      p_company_id,'customer_service',r.created_by,null
    )
    and (
      nullif(trim(p_query),'') is null
      or r.reservation_number ilike '%'||p_query||'%'
      or r.customer_name ilike '%'||p_query||'%'
      or r.car_name ilike '%'||p_query||'%'
    )
  order by r.start_date desc,r.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- 2. Quick Search validates the ownership of every returned business record.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r85_search_result_visible(
  p_company_id uuid,p_type text,p_id text
) returns boolean
language plpgsql stable security definer set search_path=public as $$
declare
  v_type text:=btrim(coalesce(p_type,''));
  v_creator uuid;
  v_module text;
  v_parent uuid;
  v_slug text;
  v_creator_text text;
begin
  if auth.uid() is null or public.is_company_admin(p_company_id) then return true; end if;

  if v_type='السيارات' then
    select created_by into v_creator from public.erp_cars
    where company_id=p_company_id and id=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'cars',v_creator,null);
  elsif v_type='المنتجات' then
    select created_by into v_creator from public.erp_inventory
    where company_id=p_company_id and id=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'inventory',v_creator,null);
  elsif v_type='المخازن' then
    select created_by into v_creator from public.erp_warehouses
    where company_id=p_company_id and id=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'warehouses',v_creator,null);
  elsif v_type='العملاء' then
    select created_by into v_creator from public.erp_customers
    where company_id=p_company_id and id=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'customers',v_creator,null);
  elsif v_type in ('المجهزون','الموردون') then
    select created_by into v_creator from public.erp_suppliers
    where company_id=p_company_id and id=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'suppliers',v_creator,null);
  elsif v_type='أوامر البيع' then
    select created_by into v_creator from public.erp_sales_orders_cloud
    where company_id=p_company_id and id::text=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'sales',v_creator,null);
  elsif v_type='أوامر الشراء' then
    select created_by into v_creator from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id::text=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'purchases',v_creator,null);
  elsif v_type='الصيانة' then
    select created_by into v_creator from public.erp_maintenance_orders
    where company_id=p_company_id and id::text=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'maintenance',v_creator,null);
  elsif v_type='خدمة العملاء' then
    select created_by into v_creator from public.erp_service_cases
    where company_id=p_company_id and id::text=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'customer_service',v_creator,null);
  elsif v_type='القيود المحاسبية' then
    select created_by into v_creator from public.erp_journal_entries
    where company_id=p_company_id and id=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'accounting',v_creator,null);
  elsif v_type='الدفعات' then
    select created_by into v_creator from public.erp_installments
    where company_id=p_company_id and id=p_id and not is_deleted limit 1;
    return public.erp_r84_record_visible(p_company_id,'installments',v_creator,null);
  elsif v_type in ('التجهيز','الاستلام','الفواتير') then
    select module,parent_id into v_module,v_parent
    from public.erp_commercial_workflow_documents
    where company_id=p_company_id and id::text=p_id and not is_deleted limit 1;
    if v_module='sales' then
      select created_by into v_creator from public.erp_sales_orders_cloud
      where company_id=p_company_id and id=v_parent and not is_deleted limit 1;
      return public.erp_r84_record_visible(p_company_id,'sales',v_creator,null);
    elsif v_module='purchases' then
      select created_by into v_creator from public.erp_purchase_orders_cloud
      where company_id=p_company_id and id=v_parent and not is_deleted limit 1;
      return public.erp_r84_record_visible(p_company_id,'purchases',v_creator,null);
    end if;
  elsif v_type='الفرص التجارية' then
    select slug into v_slug from public.companies
    where id=p_company_id and is_active limit 1;
    select coalesce(payload->>'createdByUserId',payload->>'createdBy','')
      into v_creator_text
    from public.erp_records
    where company_id=v_slug and entity_type='opportunities' and record_id=p_id
      and deleted_at is null and not is_deleted limit 1;
    return public.erp_r84_record_visible(
      p_company_id,'customer_service',null,v_creator_text
    );
  end if;

  -- Unknown search categories retain their previous visibility. Every category
  -- emitted by the current global search is handled above.
  return true;
end;
$$;
revoke all on function public.erp_r85_search_result_visible(uuid,text,text)
  from public,anon,authenticated;

create or replace function public.erp_r49_cloud_global_search(
  p_company_id uuid,p_query text,p_limit integer default 50
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  with base as (
    select x
    from public.erp_r9_cloud_global_search(p_company_id,p_query,least(coalesce(p_limit,50),100)) x
    where public.erp_r85_search_result_visible(
      p_company_id,x->>'type',x->>'id'
    )
  ), enriched as (
    select case
      when x->>'type'='أوامر البيع' then x||jsonb_build_object(
        'currency',coalesce((select o.currency from public.erp_sales_orders_cloud o
          where o.company_id=p_company_id and o.id::text=x->>'id' limit 1),'USD'))
      when x->>'type'='أوامر الشراء' then x||jsonb_build_object(
        'currency',coalesce((select o.currency from public.erp_purchase_orders_cloud o
          where o.company_id=p_company_id and o.id::text=x->>'id' limit 1),'USD'))
      when x->>'type' in ('التجهيز','الاستلام','الفواتير') then x||jsonb_build_object(
        'currency',coalesce((select d.payload->>'currency'
          from public.erp_commercial_workflow_documents d
          where d.company_id=p_company_id and d.id::text=x->>'id' limit 1),'USD'))
      else x end x
    from base
  ), opportunities as (
    select jsonb_build_object(
      'id',r.record_id,
      'type','الفرص التجارية',
      'title',concat_ws(' • ',coalesce(r.payload->>'opportunityNumber','OPP'),
        coalesce(r.payload->>'customerName','')),
      'subtitle',concat_ws(' • ',coalesce(r.payload->>'status',''),
        coalesce(r.payload->>'salesOrderNumber',''),
        coalesce(r.payload->>'maintenanceOrderNumber','')),
      'route','customer-service',
      'businessReference',coalesce(r.payload->>'opportunityNumber',r.record_id),
      'relatedSalesNumber',r.payload->>'salesOrderNumber',
      'relatedMaintenanceNumber',r.payload->>'maintenanceOrderNumber',
      'currency',coalesce(r.payload->>'currency','USD'),
      'updatedAt',r.updated_at
    ) x
    from public.erp_records r
    join public.companies c on c.slug=r.company_id
    where c.id=p_company_id and r.entity_type='opportunities'
      and r.deleted_at is null and not r.is_deleted
      and public.erp_r84_record_visible(
        p_company_id,'customer_service',null,
        coalesce(r.payload->>'createdByUserId',r.payload->>'createdBy','')
      )
      and (
        coalesce(trim(p_query),'')=''
        or coalesce(r.payload->>'opportunityNumber','') ilike '%'||trim(p_query)||'%'
        or coalesce(r.payload->>'customerName','') ilike '%'||trim(p_query)||'%'
        or coalesce(r.payload->>'salesOrderNumber','') ilike '%'||trim(p_query)||'%'
        or coalesce(r.payload->>'maintenanceOrderNumber','') ilike '%'||trim(p_query)||'%'
      )
  )
  select x from (
    select x from enriched
    union all
    select x from opportunities
  ) all_rows
  order by coalesce(x->>'updatedAt','') desc,x->>'title'
  limit least(coalesce(p_limit,50),100);
$$;
revoke all on function public.erp_r49_cloud_global_search(uuid,text,integer)
  from public,anon;
grant execute on function public.erp_r49_cloud_global_search(uuid,text,integer)
  to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 3. Scope-aware report section filtering. Every current detailed section
-- carries createdBy/performedBy metadata. If a future section omits creator
-- metadata while records.own is active, it fails closed with an empty row set.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r85_current_creator_aliases(p_company_id uuid)
returns text[]
language plpgsql stable security definer set search_path=public as $$
declare
  v_slug text;
  v_user_id text;
  v_payload jsonb:='{}'::jsonb;
  v_values text[];
  v_result text[];
begin
  select slug into v_slug from public.companies
  where id=p_company_id and is_active limit 1;
  v_user_id:=public.erp_current_cloud_erp_user_id(p_company_id);
  if v_slug is not null and v_user_id is not null then
    select payload into v_payload from public.erp_records
    where company_id=v_slug and entity_type='users' and record_id=v_user_id
      and deleted_at is null and not is_deleted limit 1;
  end if;
  v_values:=array[
    auth.uid()::text,
    auth.jwt()->>'email',
    v_user_id,
    v_payload->>'email',
    v_payload->>'fullName',
    v_payload->>'username'
  ];
  select coalesce(array_agg(distinct lower(btrim(v))),'{}'::text[])
    into v_result
  from unnest(v_values) v
  where nullif(btrim(coalesce(v,'')),'') is not null;
  return v_result;
end;
$$;

create or replace function public.erp_r85_report_default_resource(p_module text)
returns text language sql immutable as $$
  select case lower(btrim(coalesce(p_module,'')))
    when 'cars' then 'cars'
    when 'products' then 'inventory'
    when 'inventory' then 'inventory'
    when 'warehouses' then 'warehouses'
    when 'customers' then 'customers'
    when 'suppliers' then 'suppliers'
    when 'sales' then 'sales'
    when 'purchases' then 'purchases'
    when 'maintenance' then 'maintenance'
    when 'customer_service' then 'customer_service'
    when 'opportunities' then 'customer_service'
    when 'payments' then 'accounting'
    when 'accounting' then 'accounting'
    when 'finance' then 'accounting'
    else null end;
$$;

create or replace function public.erp_r85_report_section_resource(
  p_key text,p_default text
) returns text language sql immutable as $$
  select case
    when lower(coalesce(p_key,'')) like '%customer%' then 'customers'
    when lower(coalesce(p_key,'')) like '%supplier%' then 'suppliers'
    when lower(coalesce(p_key,'')) like '%warehouse%' then 'warehouses'
    when lower(coalesce(p_key,'')) like '%product%'
      or lower(coalesce(p_key,'')) like '%inventory%' then 'inventory'
    when lower(coalesce(p_key,'')) like '%car%'
      or lower(coalesce(p_key,'')) like '%vehicle%' then 'cars'
    when lower(coalesce(p_key,'')) like '%purchase%' then 'purchases'
    when lower(coalesce(p_key,'')) like '%sale%' then 'sales'
    when lower(coalesce(p_key,'')) like '%maintenance%' then 'maintenance'
    when lower(coalesce(p_key,'')) like '%cash%' then 'cashbox'
    when lower(coalesce(p_key,'')) like '%journal%'
      or lower(coalesce(p_key,'')) like '%account%' then 'accounting'
    when lower(coalesce(p_key,'')) like '%installment%' then 'installments'
    when lower(coalesce(p_key,'')) like '%opportunit%'
      or lower(coalesce(p_key,'')) like '%service%'
      or lower(coalesce(p_key,'')) like '%reservation%'
      or lower(coalesce(p_key,'')) like '%partner_activit%' then 'customer_service'
    else p_default end;
$$;

create or replace function public.erp_r85_filter_report_sections(
  p_company_id uuid,p_default_resource text,p_sections jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='[]'::jsonb;
  v_section jsonb;
  v_rows jsonb;
  v_resource text;
  v_index integer;
  v_aliases text[]:=public.erp_r85_current_creator_aliases(p_company_id);
begin
  if jsonb_typeof(coalesce(p_sections,'[]'::jsonb))<>'array' then return '[]'::jsonb; end if;
  for v_section in select value from jsonb_array_elements(p_sections) loop
    v_resource:=public.erp_r85_report_section_resource(
      v_section->>'key',p_default_resource
    );
    if v_resource is null
       or public.erp_r84_record_scope_mode(p_company_id,v_resource)='all' then
      v_result:=v_result||jsonb_build_array(v_section);
      continue;
    end if;

    v_index:=null;
    select (c.ordinality-1)::integer into v_index
    from jsonb_array_elements_text(coalesce(v_section->'columns','[]'::jsonb))
      with ordinality c(value,ordinality)
    where lower(replace(replace(c.value,'_',''),' ','')) in (
      'createdby','createdbyuser','createdbyusername','performedby'
    )
    order by c.ordinality
    limit 1;

    if v_index is null then
      v_rows:='[]'::jsonb;
    else
      select coalesce(jsonb_agg(r.value),'[]'::jsonb) into v_rows
      from jsonb_array_elements(coalesce(v_section->'rows','[]'::jsonb)) r(value)
      where lower(btrim(coalesce(r.value->>v_index,'')))=any(v_aliases)
         or lower(btrim(coalesce(r.value->>v_index,''))) in ('system','النظام');
    end if;
    v_section:=jsonb_set(v_section,'{rows}',v_rows,true);
    v_result:=v_result||jsonb_build_array(v_section);
  end loop;
  return v_result;
end;
$$;

revoke all on function public.erp_r85_current_creator_aliases(uuid) from public,anon,authenticated;
revoke all on function public.erp_r85_report_default_resource(text) from public,anon,authenticated;
revoke all on function public.erp_r85_report_section_resource(text,text) from public,anon,authenticated;
revoke all on function public.erp_r85_filter_report_sections(uuid,text,jsonb) from public,anon,authenticated;

create or replace function public.erp_r9_cloud_contextual_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_raw jsonb;
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.contextual.view') then
    raise exception 'permission_denied:reports.contextual.view' using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(
    p_company_id,'reports','contextualDetails','reports.view'
  ) then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  v_raw:=public.erp_cloud_contextual_report(
    p_company_id,p_module,p_start_date,p_end_date
  );
  return public.erp_r85_filter_report_sections(
    p_company_id,public.erp_r85_report_default_resource(p_module),v_raw
  );
end;
$$;

create or replace function public.erp_r9_cloud_model_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_raw jsonb;
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.contextual.view') then
    raise exception 'permission_denied:reports.contextual.view' using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(
    p_company_id,'reports','contextualDetails','reports.view'
  ) then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  v_raw:=public.erp_cloud_model_report(
    p_company_id,p_module,p_start_date,p_end_date
  );
  return public.erp_r85_filter_report_sections(
    p_company_id,public.erp_r85_report_default_resource(p_module),v_raw
  );
end;
$$;

create or replace function public.erp_r9_cloud_customer_service_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_raw jsonb; v_filtered jsonb;
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.contextual.view') then
    raise exception 'permission_denied:reports.contextual.view' using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(
    p_company_id,'reports','contextualDetails','reports.view'
  ) then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_raw
  from public.erp_cloud_customer_service_report(
    p_company_id,p_module,p_start_date,p_end_date
  ) x;
  v_filtered:=public.erp_r85_filter_report_sections(
    p_company_id,'customer_service',v_raw
  );
  return query select value from jsonb_array_elements(v_filtered);
end;
$$;

grant execute on function public.erp_r9_cloud_contextual_report(uuid,text,date,date)
  to authenticated,service_role;
grant execute on function public.erp_r9_cloud_model_report(uuid,text,date,date)
  to authenticated,service_role;
grant execute on function public.erp_r9_cloud_customer_service_report(uuid,text,date,date)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
