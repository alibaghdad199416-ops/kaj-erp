\set ON_ERROR_STOP on
begin;

-- R93 negative-runtime proof. Everything created here is rolled back.
set local role postgres;

do $$
declare
  v_company constant uuid := '11111111-1111-4111-8111-111111111111';
  v_user constant uuid := '93939393-9393-4393-8393-939393939393';
  v_local_user constant text := 'r93-restricted-user';
  v_code text;
  v_permission_id text;
begin
  -- Minimal local-only auth identity used solely to satisfy the membership FK.
  insert into auth.users(id,aud,role)
  values(v_user,'authenticated','authenticated')
  on conflict(id) do nothing;

  insert into public.company_memberships(
    company_id,user_id,user_uid,local_user_id,default_branch_id,
    role_code,is_system_admin,is_active,updated_at
  ) values (
    v_company,v_user,v_user::text,v_local_user,
    '22222222-2222-4222-8222-222222222222','r93_restricted',false,true,now()
  ) on conflict(company_id,user_id) do update set
    user_uid=excluded.user_uid,local_user_id=excluded.local_user_id,
    role_code=excluded.role_code,is_system_admin=false,is_active=true,updated_at=now();

  insert into public.erp_records(
    company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
  ) values (
    'quality-line','users',v_local_user,
    jsonb_build_object(
      'id',v_local_user,'fullName','R93 Restricted Runtime User',
      'roleId','r93-restricted-role','cloudAuthUid',v_user::text,'isActive',true
    ),false,null,now()
  ) on conflict(company_id,entity_type,record_id) do update set
    payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

  insert into public.erp_records(
    company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
  ) values (
    'quality-line','user_permission_overrides',v_local_user,
    jsonb_build_object('userId',v_local_user,'enabled',true),false,null,now()
  ) on conflict(company_id,entity_type,record_id) do update set
    payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

  foreach v_code in array array[
    'sales.view',
    'sales.update',
    'sales.fields.restrict',
    'sales.fields.itemWarehouse.view',
    'purchases.view',
    'warehouses.view',
    'warehouses.fields.restrict'
  ] loop
    v_permission_id := 'r93-perm-'||substr(md5(v_code),1,20);
    insert into public.erp_records(
      company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
    ) values (
      'quality-line','permissions',v_permission_id,
      jsonb_build_object(
        'id',v_permission_id,'code',v_code,'name',v_code,
        'module',split_part(v_code,'.',1),'description','R93 runtime permission fixture'
      ),false,null,now()
    ) on conflict(company_id,entity_type,record_id) do update set
      payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

    insert into public.erp_records(
      company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
    ) values (
      'quality-line','user_permissions',v_local_user||'::'||v_permission_id,
      jsonb_build_object('userId',v_local_user,'permissionId',v_permission_id),
      false,null,now()
    ) on conflict(company_id,entity_type,record_id) do update set
      payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
  end loop;

  insert into public.erp_warehouses(
    company_id,id,data,created_by,updated_by
  ) values (
    v_company,'r93-hidden-warehouse',
    jsonb_build_object(
      'id','r93-hidden-warehouse','code','R93-HIDDEN','name','R93 Hidden Warehouse',
      'address','R93 restricted field proof','isActive',true
    ),v_user,v_user
  ) on conflict(company_id,id) do update set
    data=excluded.data,updated_by=excluded.updated_by,updated_at=now();
end $$;

select set_config(
  'request.jwt.claims',
  '{"sub":"93939393-9393-4393-8393-939393939393","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_company constant uuid := '11111111-1111-4111-8111-111111111111';
  v_masked jsonb;
begin
  if not public.erp_cloud_user_has_permission(v_company,'sales.view') then
    raise exception 'r93_restricted_user_base_permission_missing';
  end if;
  if public.erp_cloud_user_has_permission(v_company,'sales.delete') then
    raise exception 'r93_restricted_user_unexpected_sales_delete';
  end if;
  if public.erp_cloud_user_has_permission(v_company,'purchases.delete') then
    raise exception 'r93_restricted_user_unexpected_purchases_delete';
  end if;

  if not public.erp_cloud_user_can_view_field(
    v_company,'sales','itemWarehouse','sales.view'
  ) then
    raise exception 'r93_sales_item_warehouse_permission_fixture_invalid';
  end if;
  if public.erp_cloud_user_can_view_field(
    v_company,'warehouses','name','warehouses.view'
  ) or public.erp_cloud_user_can_view_field(
    v_company,'warehouses','code','warehouses.view'
  ) then
    raise exception 'r93_hidden_warehouse_identity_field_unexpectedly_visible';
  end if;

  -- Direct Data API equivalent must be hidden by RLS in restricted mode.
  if exists(
    select 1 from public.erp_warehouses
    where company_id=v_company and id='r93-hidden-warehouse'
  ) then
    raise exception 'r93_restricted_raw_warehouse_row_leaked';
  end if;

  -- Guarded master read can keep technical identity, never hidden business fields.
  select row_value into v_masked
  from public.erp_r9_list_cloud_master_records(
    v_company,'erp_warehouses'
  ) as t(row_value)
  where row_value->>'id'='r93-hidden-warehouse'
  limit 1;
  if v_masked is null then
    raise exception 'r93_masked_warehouse_fixture_not_returned';
  end if;
  if v_masked ? 'name' or v_masked ? 'code' or v_masked ? 'address' then
    raise exception 'r93_masked_warehouse_business_field_leaked:%',v_masked;
  end if;

  -- Workflow selectors must not expose a hidden warehouse technical id.
  if exists(
    select 1
    from public.erp_r92_list_workflow_warehouses(v_company,'sales') as t(row_value)
    where row_value->>'id'='r93-hidden-warehouse'
  ) then
    raise exception 'r93_workflow_warehouse_selector_leaked_hidden_identity';
  end if;

  begin
    perform public.erp_r92_delete_cloud_sale(v_company,'r93-missing-sale');
    raise exception 'r93_sales_delete_without_permission_unexpectedly_succeeded';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.erp_r92_delete_cloud_purchase(v_company,'r93-missing-purchase');
    raise exception 'r93_purchase_delete_without_permission_unexpectedly_succeeded';
  exception when sqlstate '42501' then
    null;
  end;
end $$;

rollback;
select 'R93 restricted-user LOCAL PostgreSQL runtime PASS' as result;
