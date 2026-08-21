-- Quality Line ERP / KAJ ERP R98
-- Maintenance record-scope closure: OWN / ASSIGNED / TEAM / ALL.
-- Forward-only. Historical migrations remain immutable.
begin;

-- ---------------------------------------------------------------------------
-- 1. Canonical record-scope permissions.
-- ---------------------------------------------------------------------------
with resources(resource,name_ar,name_en) as (
  values
    ('customers','العملاء','customers'),
    ('suppliers','الموردون','suppliers'),
    ('cars','السيارات','vehicles'),
    ('inventory','المخزون','inventory'),
    ('warehouses','المخازن','warehouses'),
    ('customer_service','خدمة العملاء','customer service'),
    ('sales','المبيعات','sales'),
    ('purchases','المشتريات','purchases'),
    ('maintenance','الصيانة','maintenance'),
    ('accounting','المحاسبة','accounting'),
    ('cashbox','الصناديق','cashboxes'),
    ('expenses','المصروفات','expenses'),
    ('installments','الأقساط','installments')
), scope_permissions(code,name_ar,name_en) as (
  select resource||'.records.assigned',
    'عرض السجلات المسندة للمستخدم - '||name_ar,
    'View records assigned to the user - '||name_en
  from resources
  union all
  select resource||'.records.team',
    'عرض سجلات فريق المستخدم - '||name_ar,
    'View records assigned to the user team - '||name_en
  from resources
)
insert into public.permissions(code,name_ar,name_en)
select code,name_ar,name_en from scope_permissions
on conflict(code) do update set
  name_ar=excluded.name_ar,
  name_en=excluded.name_en;

do $$
declare c record;
begin
  if to_regprocedure('public.erp_seed_access_catalog(uuid)') is not null then
    for c in select id from public.companies where is_active loop
      perform public.erp_seed_access_catalog(c.id);
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Explicit team membership and per-record assignment.
-- Direct browser table access is forbidden; mutation is RPC-only.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_record_scope_teams (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id,name)
);

create table if not exists public.erp_record_scope_team_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  team_id uuid not null references public.erp_record_scope_teams(id) on delete cascade,
  auth_user_id uuid,
  erp_user_id text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check(auth_user_id is not null or nullif(btrim(erp_user_id),'') is not null)
);
create index if not exists erp_record_scope_team_members_lookup_idx
  on public.erp_record_scope_team_members(company_id,team_id,auth_user_id,erp_user_id);

create table if not exists public.erp_record_scope_assignments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  resource text not null,
  record_id text not null,
  assigned_auth_user_id uuid,
  assigned_erp_user_id text,
  team_id uuid references public.erp_record_scope_teams(id) on delete set null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id,resource,record_id),
  check(
    assigned_auth_user_id is not null
    or nullif(btrim(assigned_erp_user_id),'') is not null
    or team_id is not null
  )
);
create index if not exists erp_record_scope_assignment_user_idx
  on public.erp_record_scope_assignments(
    company_id,resource,assigned_auth_user_id,assigned_erp_user_id
  );
create index if not exists erp_record_scope_assignment_team_idx
  on public.erp_record_scope_assignments(company_id,resource,team_id);

alter table public.erp_record_scope_teams enable row level security;
alter table public.erp_record_scope_team_members enable row level security;
alter table public.erp_record_scope_assignments enable row level security;
revoke all on table public.erp_record_scope_teams from public,anon,authenticated;
revoke all on table public.erp_record_scope_team_members from public,anon,authenticated;
revoke all on table public.erp_record_scope_assignments from public,anon,authenticated;
grant all on table public.erp_record_scope_teams to service_role;
grant all on table public.erp_record_scope_team_members to service_role;
grant all on table public.erp_record_scope_assignments to service_role;

-- ---------------------------------------------------------------------------
-- 3. Shared union visibility engine.
-- ALL short-circuits. OWN, ASSIGNED and TEAM are additive, not exclusive.
-- Users without any new scope keep the exact R84 compatibility behavior.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r98_record_visible(
  p_company_id uuid,
  p_resource text,
  p_record_id text,
  p_created_by uuid default null,
  p_created_by_text text default null
) returns boolean
language plpgsql stable security definer set search_path=public as $$
declare
  v_resource text:=btrim(coalesce(p_resource,''));
  v_record_id text:=btrim(coalesce(p_record_id,''));
  v_auth uuid:=auth.uid();
  v_auth_text text:=coalesce(auth.uid()::text,'');
  v_erp_user text:=coalesce(public.erp_current_cloud_erp_user_id(p_company_id),'');
  v_creator text:=btrim(coalesce(p_created_by_text,''));
  v_own boolean;
  v_assigned boolean;
  v_team boolean;
  v_all boolean;
  v_has_new_scope boolean;
begin
  if p_company_id is null or v_resource='' then return false; end if;
  if v_auth is null then return true; end if;
  if not public.is_active_company_member(p_company_id) then return false; end if;
  if public.is_company_admin(p_company_id) then return true; end if;

  v_all:=public.erp_cloud_user_has_permission(
    p_company_id,v_resource||'.records.all'
  );
  if v_all then return true; end if;

  v_own:=public.erp_cloud_user_has_permission(
    p_company_id,v_resource||'.records.own'
  );
  v_assigned:=public.erp_cloud_user_has_permission(
    p_company_id,v_resource||'.records.assigned'
  );
  v_team:=public.erp_cloud_user_has_permission(
    p_company_id,v_resource||'.records.team'
  );
  v_has_new_scope:=v_assigned or v_team;

  -- No R98 scope selected: preserve the exact R84 migration compatibility
  -- semantics, including the existing override fallback behavior.
  if not v_has_new_scope then
    return public.erp_r84_record_visible(
      p_company_id,v_resource,p_created_by,p_created_by_text
    );
  end if;

  if v_own and (
    (p_created_by is not null and p_created_by=v_auth)
    or (v_creator<>'' and v_creator in (v_auth_text,v_erp_user))
  ) then return true; end if;

  if v_record_id='' then return false; end if;

  if v_assigned and exists(
    select 1
    from public.erp_record_scope_assignments a
    where a.company_id=p_company_id
      and a.resource=v_resource
      and a.record_id=v_record_id
      and (
        a.assigned_auth_user_id=v_auth
        or (v_erp_user<>'' and a.assigned_erp_user_id=v_erp_user)
      )
  ) then return true; end if;

  if v_team and exists(
    select 1
    from public.erp_record_scope_assignments a
    join public.erp_record_scope_team_members m
      on m.company_id=a.company_id and m.team_id=a.team_id
    join public.erp_record_scope_teams t
      on t.company_id=a.company_id and t.id=a.team_id and t.is_active
    where a.company_id=p_company_id
      and a.resource=v_resource
      and a.record_id=v_record_id
      and (
        m.auth_user_id=v_auth
        or (v_erp_user<>'' and m.erp_user_id=v_erp_user)
      )
  ) then return true; end if;

  return false;
end;
$$;

create or replace function public.erp_r98_require_maintenance_order_visible(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql stable security definer set search_path=public as $$
declare v_creator uuid;
begin
  select created_by into v_creator
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found or not public.erp_r98_record_visible(
    p_company_id,'maintenance',p_order_id::text,v_creator,null
  ) then
    raise exception 'maintenance_order_not_found' using errcode='P0002';
  end if;
end;
$$;

revoke all on function public.erp_r98_record_visible(uuid,text,text,uuid,text)
  from public,anon;
revoke all on function public.erp_r98_require_maintenance_order_visible(uuid,uuid)
  from public,anon;
grant execute on function public.erp_r98_record_visible(uuid,text,text,uuid,text)
  to authenticated,service_role;
grant execute on function public.erp_r98_require_maintenance_order_visible(uuid,uuid)
  to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 4. Governed scope administration. No client can mutate scope tables directly.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r98_save_record_scope_team(
  p_company_id uuid,p_team_id uuid,p_name text,p_is_active boolean default true
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=coalesce(p_team_id,gen_random_uuid());
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(
    p_company_id,'permissions.scopes.manage'
  ) then raise exception 'permission_denied:permissions.scopes.manage' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_name,'')),'') is null then
    raise exception 'record_scope_team_name_required';
  end if;
  insert into public.erp_record_scope_teams(
    id,company_id,name,is_active,created_by,created_at,updated_at
  ) values(
    v_id,p_company_id,btrim(p_name),coalesce(p_is_active,true),auth.uid(),now(),now()
  )
  on conflict(id) do update set
    name=excluded.name,is_active=excluded.is_active,updated_at=now()
  where public.erp_record_scope_teams.company_id=p_company_id;
  return v_id;
end;
$$;

create or replace function public.erp_r98_set_record_scope_team_members(
  p_company_id uuid,p_team_id uuid,p_members jsonb
) returns integer
language plpgsql security definer set search_path=public as $$
declare v_row jsonb; v_count integer:=0; v_auth uuid; v_erp text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(
    p_company_id,'permissions.scopes.manage'
  ) then raise exception 'permission_denied:permissions.scopes.manage' using errcode='42501'; end if;
  if not exists(
    select 1 from public.erp_record_scope_teams
    where company_id=p_company_id and id=p_team_id
  ) then raise exception 'record_scope_team_not_found'; end if;
  delete from public.erp_record_scope_team_members
  where company_id=p_company_id and team_id=p_team_id;
  for v_row in select value from jsonb_array_elements(coalesce(p_members,'[]'::jsonb)) loop
    begin v_auth:=nullif(v_row->>'authUserId','')::uuid;
    exception when others then raise exception 'invalid_scope_auth_user'; end;
    v_erp:=nullif(btrim(coalesce(v_row->>'erpUserId','')),'');
    if v_auth is null and v_erp is null then continue; end if;
    if v_auth is not null and not exists(
      select 1 from public.company_memberships cm
      where cm.company_id=p_company_id and cm.user_id=v_auth and cm.is_active
    ) then raise exception 'scope_user_not_company_member'; end if;
    insert into public.erp_record_scope_team_members(
      company_id,team_id,auth_user_id,erp_user_id,created_by
    ) values(p_company_id,p_team_id,v_auth,v_erp,auth.uid());
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.erp_r98_assign_record_scope(
  p_company_id uuid,p_resource text,p_record_id text,
  p_assigned_auth_user_id uuid default null,
  p_assigned_erp_user_id text default null,
  p_team_id uuid default null
) returns void
language plpgsql security definer set search_path=public as $$
declare v_resource text:=btrim(coalesce(p_resource,'')); v_record text:=btrim(coalesce(p_record_id,''));
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(
    p_company_id,'permissions.scopes.manage'
  ) then raise exception 'permission_denied:permissions.scopes.manage' using errcode='42501'; end if;
  if v_resource not in (
    'customers','suppliers','cars','inventory','warehouses','customer_service',
    'sales','purchases','maintenance','accounting','cashbox','expenses','installments'
  ) then raise exception 'invalid_record_scope_resource'; end if;
  if v_record='' then raise exception 'record_scope_record_required'; end if;
  if p_assigned_auth_user_id is null
     and nullif(btrim(coalesce(p_assigned_erp_user_id,'')),'') is null
     and p_team_id is null then
    delete from public.erp_record_scope_assignments
    where company_id=p_company_id and resource=v_resource and record_id=v_record;
    return;
  end if;
  if p_team_id is not null and not exists(
    select 1 from public.erp_record_scope_teams
    where company_id=p_company_id and id=p_team_id and is_active
  ) then raise exception 'record_scope_team_not_found'; end if;
  if p_assigned_auth_user_id is not null and not exists(
    select 1 from public.company_memberships cm
    where cm.company_id=p_company_id and cm.user_id=p_assigned_auth_user_id and cm.is_active
  ) then raise exception 'scope_user_not_company_member'; end if;
  insert into public.erp_record_scope_assignments(
    company_id,resource,record_id,assigned_auth_user_id,assigned_erp_user_id,
    team_id,created_by,created_at,updated_at
  ) values(
    p_company_id,v_resource,v_record,p_assigned_auth_user_id,
    nullif(btrim(coalesce(p_assigned_erp_user_id,'')),''),p_team_id,
    auth.uid(),now(),now()
  ) on conflict(company_id,resource,record_id) do update set
    assigned_auth_user_id=excluded.assigned_auth_user_id,
    assigned_erp_user_id=excluded.assigned_erp_user_id,
    team_id=excluded.team_id,updated_at=now();
end;
$$;

revoke all on function public.erp_r98_save_record_scope_team(uuid,uuid,text,boolean) from public,anon;
revoke all on function public.erp_r98_set_record_scope_team_members(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_r98_assign_record_scope(uuid,text,text,uuid,text,uuid) from public,anon;
grant execute on function public.erp_r98_save_record_scope_team(uuid,uuid,text,boolean) to authenticated,service_role;
grant execute on function public.erp_r98_set_record_scope_team_members(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r98_assign_record_scope(uuid,text,text,uuid,text,uuid) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 5. Maintenance is the first fully migrated ASSIGNED/TEAM resource.
-- Existing orders are assigned to their creator so enabling ASSIGNED cannot
-- unexpectedly hide historical records before an administrator reassigns them.
-- ---------------------------------------------------------------------------
insert into public.erp_record_scope_assignments(
  company_id,resource,record_id,assigned_auth_user_id,created_by
)
select o.company_id,'maintenance',o.id::text,o.created_by,o.created_by
from public.erp_maintenance_orders o
where not o.is_deleted and o.created_by is not null
on conflict(company_id,resource,record_id) do nothing;

create or replace function public.erp_r98_maintenance_scope_guard()
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
  if not public.erp_r98_record_visible(
    old.company_id,'maintenance',old.id::text,old.created_by,null
  ) then
    raise exception 'record_scope_denied:maintenance' using errcode='42501';
  end if;
  if tg_op='UPDATE' then
    new.created_by:=old.created_by;
    return new;
  end if;
  return old;
end;
$$;

create or replace function public.erp_r98_sync_maintenance_assignment()
returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_op='DELETE' then
    delete from public.erp_record_scope_assignments
    where company_id=old.company_id and resource='maintenance' and record_id=old.id::text;
    return old;
  end if;
  insert into public.erp_record_scope_assignments(
    company_id,resource,record_id,assigned_auth_user_id,created_by
  ) values(new.company_id,'maintenance',new.id::text,new.created_by,new.created_by)
  on conflict(company_id,resource,record_id) do nothing;
  return new;
end;
$$;

drop trigger if exists aa_r84_record_scope_guard on public.erp_maintenance_orders;
drop trigger if exists aa_r98_record_scope_guard on public.erp_maintenance_orders;
create trigger aa_r98_record_scope_guard
before insert or update or delete on public.erp_maintenance_orders
for each row execute function public.erp_r98_maintenance_scope_guard();

drop trigger if exists zz_r98_maintenance_assignment_sync on public.erp_maintenance_orders;
create trigger zz_r98_maintenance_assignment_sync
after insert or delete on public.erp_maintenance_orders
for each row execute function public.erp_r98_sync_maintenance_assignment();

revoke all on function public.erp_r98_maintenance_scope_guard() from public,anon,authenticated;
revoke all on function public.erp_r98_sync_maintenance_assignment() from public,anon,authenticated;
grant execute on function public.erp_r98_maintenance_scope_guard() to service_role;
grant execute on function public.erp_r98_sync_maintenance_assignment() to service_role;

-- ---------------------------------------------------------------------------
-- 6. Maintenance list/line/detail readers now use the R98 visibility engine.
-- Field masking remains owned by the established R9/R89/R90 contracts.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_list_cloud_maintenance_orders(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(
    p_company_id,'maintenance',to_jsonb(x),'maintenance.view'
  )
  from public.erp_list_cloud_maintenance_orders(p_company_id) x
  join public.erp_maintenance_orders o
    on o.company_id=p_company_id and o.id::text=to_jsonb(x)->>'id' and not o.is_deleted
  where public.erp_r98_record_visible(
    p_company_id,'maintenance',o.id::text,o.created_by,null
  );
$$;

create or replace function public.erp_r9_get_cloud_maintenance_order_lines(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(
      p_company_id,'maintenance',to_jsonb(x),'maintenance.view'
    )
    || case
      when public.erp_cloud_user_can_view_field(
        p_company_id,'maintenance','items','maintenance.view'
      ) then jsonb_build_object(
        'description',coalesce(
          nullif(btrim(i.data->>'description'),''),
          nullif(btrim(i.data->>'descriptionAr'),''),
          nullif(btrim(i.data->>'descriptionEn'),''),
          nullif(btrim(i.data->>'notes'),''),
          nullif(btrim(x."productName"),''),
          ''
        )
      ) else '{}'::jsonb end
  from public.erp_get_cloud_maintenance_order_lines(p_company_id,p_order_id) x
  join public.erp_maintenance_parts mp
    on mp.company_id=p_company_id and mp.id=x.id and not mp.is_deleted
  left join public.erp_inventory i
    on i.company_id=mp.company_id
   and i.id=coalesce(mp.source_product_id,mp.product_id::text)
   and not i.is_deleted
  where exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
      and public.erp_r98_record_visible(
        p_company_id,'maintenance',o.id::text,o.created_by,null
      )
  );
$$;

create or replace function public.erp_r89_maintenance_cost_reconciliation(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_payload jsonb;
begin
  perform public.erp_r98_require_maintenance_order_visible(p_company_id,p_order_id);
  v_payload:=public.erp_r57_maintenance_cost_reconciliation(p_company_id,p_order_id);
  return public.erp_r89_filter_maintenance_cost_payload(p_company_id,v_payload);
end;
$$;

create or replace function public.erp_r89_maintenance_material_issue_state(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_payload jsonb;
begin
  perform public.erp_r98_require_maintenance_order_visible(p_company_id,p_order_id);
  v_payload:=public.erp_r57_maintenance_material_issue_state(p_company_id,p_order_id);
  return public.erp_r89_filter_maintenance_cost_payload(p_company_id,v_payload);
end;
$$;

create or replace function public.erp_r89_get_maintenance_order_snapshot(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_base jsonb; v_reconciliation jsonb; v_issue jsonb;
begin
  perform public.erp_r98_require_maintenance_order_visible(p_company_id,p_order_id);
  v_base:=public.erp_r64_get_maintenance_order_snapshot(p_company_id,p_order_id);
  v_reconciliation:=public.erp_r89_maintenance_cost_reconciliation(p_company_id,p_order_id);
  v_issue:=public.erp_r89_maintenance_material_issue_state(p_company_id,p_order_id);
  return jsonb_set(
    jsonb_set(v_base,'{reconciliation}',v_reconciliation,true),
    '{issueState}',v_issue,true
  );
end;
$$;

-- Explicit current aliases used by Flutter. R98 guarantees they exist and
-- removes the draft/non-draft runtime ambiguity around the R89 snapshot names.
create or replace function public.erp_r90_get_maintenance_order_snapshot(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r89_get_maintenance_order_snapshot(p_company_id,p_order_id)
$$;

create or replace function public.erp_r90_maintenance_material_issue_state(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r89_maintenance_material_issue_state(p_company_id,p_order_id)
$$;

create or replace function public.erp_r88_list_maintenance_payments(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view')
     or not public.erp_cloud_user_can_view_field(
       p_company_id,'maintenance','payments','maintenance.view'
     ) then
    raise exception 'field_permission_denied:maintenance.payments' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
      and public.erp_r98_record_visible(
        p_company_id,'maintenance',o.id::text,o.created_by,null
      )
  ) then return; end if;
  return query
  select jsonb_build_object(
    'id',p.id,'paymentReference',coalesce(p.payment_key,p.id::text),
    'cashTransactionId',p.cash_transaction_id,
    'cashboxId',coalesce(p.payment_payload->>'cashAccountId',''),
    'cashboxName',coalesce(ca.data->>'name',''),
    'currency',upper(p.currency_code),'amount',p.amount,
    'invoiceAmount',p.amount_in_order_currency,
    'invoiceCurrency',coalesce(p.payment_payload->>'invoiceCurrency',''),
    'exchangeRate',p.exchange_rate,
    'exchangeDifference',public.erp_try_numeric(p.payment_payload->>'exchangeDifference',0),
    'paymentDate',p.payment_date,
    'userId',p.updated_by,'userName',coalesce(pr.full_name,''),
    'relatedInvoice',coalesce(o.invoice_number,''),
    'relatedOrder',o.order_number,
    'status',case when p.is_deleted then 'deleted' else 'posted' end,
    'notes',coalesce(p.notes,''),'journalEntryId',p.journal_entry_id
  )
  from public.erp_maintenance_payments p
  join public.erp_maintenance_orders o
    on o.company_id=p.company_id and o.id=p.maintenance_order_id
  left join public.erp_cash_accounts ca
    on ca.company_id=p.company_id
   and ca.id=coalesce(p.payment_payload->>'cashAccountId','')
   and not ca.is_deleted
  left join public.profiles pr on pr.id=p.updated_by
  where p.company_id=p_company_id and p.maintenance_order_id=p_order_id
    and not p.is_deleted
  order by p.payment_date desc,p.created_at desc;
end;
$$;

create or replace function public.erp_r90_list_maintenance_payments(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_r98_require_maintenance_order_visible(p_company_id,p_order_id);
  return query
  select public.erp_r90_filter_maintenance_payment(p_company_id,x)
  from public.erp_r88_list_maintenance_payments(p_company_id,p_order_id) x;
end;
$$;

-- Vehicle service history can span many maintenance orders; filter each row by
-- the same R98 order visibility contract before exposing it to R90.
create or replace function public.erp_r88_vehicle_service_card(
  p_company_id uuid,p_car_id text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb; v_vehicle jsonb; v_history jsonb:='[]'::jsonb;
  v_schedules jsonb:='[]'::jsonb; v_row jsonb; v_filtered jsonb;
  v_order public.erp_maintenance_orders%rowtype; v_creator_name text; v_details jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'cars.view')
     or not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:vehicle_service_card' using errcode='42501';
  end if;
  v_base:=public.erp_r56_vehicle_service_card(p_company_id,p_car_id);
  v_vehicle:=public.erp_r9_filter_result_json(
    p_company_id,'cars',coalesce(v_base->'vehicle','{}'::jsonb),'cars.view'
  );
  for v_row in select value from jsonb_array_elements(
    coalesce(v_base->'maintenanceHistory','[]'::jsonb)
  ) loop
    select * into v_order from public.erp_maintenance_orders o
    where o.company_id=p_company_id and o.id=(v_row->>'id')::uuid and not o.is_deleted;
    if not found then continue; end if;
    if not public.erp_r98_record_visible(
      p_company_id,'maintenance',v_order.id::text,v_order.created_by,null
    ) then continue; end if;
    select coalesce(full_name,'') into v_creator_name
      from public.profiles where id=v_order.created_by;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',d.id,'title',d.title,'description',d.description,
      'sortOrder',d.sort_order,'createdBy',d.created_by,
      'createdByName',coalesce(p.full_name,''),'createdAt',d.created_at
    ) order by d.sort_order,d.created_at),'[]'::jsonb)
    into v_details
    from public.erp_maintenance_history_details d
    left join public.profiles p on p.id=d.created_by
    where d.company_id=p_company_id and d.car_id=p_car_id
      and d.maintenance_order_id=v_order.id and not d.is_deleted;
    v_filtered:=public.erp_r9_filter_result_json(
      p_company_id,'maintenance',
      v_row||jsonb_build_object(
        'laborCost',v_order.labor_cost,'partsCost',v_order.parts_cost,
        'totalCost',v_order.total_cost,'profit',v_order.profit,
        'createdAt',v_order.created_at,'createdBy',v_order.created_by,
        'createdByName',coalesce(v_creator_name,''),
        'responsibleUser',coalesce(v_creator_name,''),
        'materialIssues',case when v_order.stock_issue_number is null then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'reference',v_order.stock_issue_number,
            'status',case when v_order.workflow_stage in(
              'stock_issue_approved','invoice_draft','invoice_approved','paid','completed'
            ) then 'approved' else 'draft' end,
            'warehouseId',v_order.source_warehouse_id,
            'warehouseName',v_row->>'warehouseName'
          )) end,
        'invoiceReferences',case when v_order.invoice_number is null then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'reference',v_order.invoice_number,'status',v_row->>'invoiceStatus'
          )) end,
        'paymentReferences',coalesce(v_row->'payments','[]'::jsonb)
      ),'maintenance.view'
    );
    if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.fields.restrict')
       or public.erp_cloud_user_can_view_field(p_company_id,'maintenance','createdBy',null) then
      v_filtered:=v_filtered||jsonb_build_object(
        'createdBy',v_order.created_by,'createdByName',coalesce(v_creator_name,''),
        'responsibleUser',coalesce(v_creator_name,'')
      );
    end if;
    if public.erp_cloud_user_can_view_field(
      p_company_id,'cars','maintenanceHistory','cars.view'
    ) then
      v_filtered:=v_filtered||jsonb_build_object(
        'materialIssues',case when v_order.stock_issue_number is null then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'reference',v_order.stock_issue_number,
            'status',case when v_order.workflow_stage in(
              'stock_issue_approved','invoice_draft','invoice_approved','paid','completed'
            ) then 'approved' else 'draft' end,
            'warehouseId',v_order.source_warehouse_id,
            'warehouseName',v_row->>'warehouseName'
          )) end,
        'invoiceReferences',case when v_order.invoice_number is null then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'reference',v_order.invoice_number,'status',v_row->>'invoiceStatus'
          )) end,
        'paymentReferences',coalesce(v_row->'payments','[]'::jsonb)
      );
    end if;
    if public.erp_cloud_user_can_view_field(
      p_company_id,'cars','maintenanceHistory','cars.view'
    ) and public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance','maintenanceHistoryDetails','maintenance.view'
    ) then
      v_filtered:=v_filtered||jsonb_build_object('customDetails',coalesce(v_details,'[]'::jsonb));
    end if;
    v_history:=v_history||jsonb_build_array(v_filtered);
  end loop;
  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_schedules
  from public.erp_r88_list_vehicle_maintenance_schedules(p_company_id,p_car_id) x;
  return jsonb_build_object(
    'vehicle',v_vehicle,'maintenanceSchedules',coalesce(v_schedules,'[]'::jsonb),
    'maintenanceHistory',v_history,'profileVersion','R98'
  );
end;
$$;

revoke all on function public.erp_r9_list_cloud_maintenance_orders(uuid) from public,anon;
revoke all on function public.erp_r9_get_cloud_maintenance_order_lines(uuid,uuid) from public,anon;
revoke all on function public.erp_r89_maintenance_cost_reconciliation(uuid,uuid) from public,anon;
revoke all on function public.erp_r89_maintenance_material_issue_state(uuid,uuid) from public,anon;
revoke all on function public.erp_r89_get_maintenance_order_snapshot(uuid,uuid) from public,anon;
revoke all on function public.erp_r90_get_maintenance_order_snapshot(uuid,uuid) from public,anon;
revoke all on function public.erp_r90_maintenance_material_issue_state(uuid,uuid) from public,anon;
revoke all on function public.erp_r88_list_maintenance_payments(uuid,uuid) from public,anon;
revoke all on function public.erp_r90_list_maintenance_payments(uuid,uuid) from public,anon;
revoke all on function public.erp_r88_vehicle_service_card(uuid,text) from public,anon;

grant execute on function public.erp_r9_list_cloud_maintenance_orders(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_get_cloud_maintenance_order_lines(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r89_maintenance_cost_reconciliation(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r89_maintenance_material_issue_state(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r89_get_maintenance_order_snapshot(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r90_get_maintenance_order_snapshot(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r90_maintenance_material_issue_state(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r88_list_maintenance_payments(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r90_list_maintenance_payments(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r88_vehicle_service_card(uuid,text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
