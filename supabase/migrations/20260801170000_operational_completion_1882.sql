-- Quality Line ERP operational completion 18.8.2.
-- Normalizes warehouse references, enriches commercial document references,
-- enables true universal recycle-bin purge, and makes per-user overrides usable.

begin;

-- Historical car rows may predate per-item accounting assignments. Metadata-only
-- updates such as warehouse alias normalization must not force those missing
-- assignments. New rows and actual account/currency changes remain strict.
create or replace function public.erp_validate_inventory_master_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := lower(coalesce(new.data->>'itemType', new.data->>'item_type', new.data->>'productType', 'stock'));
  v_currency text := upper(coalesce(new.data->>'currency', 'IQD'));
  v_asset text := nullif(coalesce(new.data->>'inventoryAssetAccountId', new.data->>'inventory_asset_account_id'), '');
  v_expense text := nullif(coalesce(new.data->>'salesCostExpenseAccountId', new.data->>'sales_cost_expense_account_id'), '');
  v_old_type text;
  v_old_currency text;
  v_old_asset text;
  v_old_expense text;
begin
  if tg_table_name = 'erp_inventory' and v_type = 'service' then
    new.data := new.data || jsonb_build_object(
      'itemType', 'service',
      'item_type', 'service',
      'productType', 'service',
      'quantity', 0,
      'minQuantity', 0,
      'minimumQuantity', 0,
      'purchasePrice', 0,
      'unitCost', 0,
      'isPurchasable', false,
      'trackInventory', false
    );
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_old_type := lower(coalesce(old.data->>'itemType', old.data->>'item_type', old.data->>'productType', 'stock'));
    v_old_currency := upper(coalesce(old.data->>'currency', 'IQD'));
    v_old_asset := nullif(coalesce(old.data->>'inventoryAssetAccountId', old.data->>'inventory_asset_account_id'), '');
    v_old_expense := nullif(coalesce(old.data->>'salesCostExpenseAccountId', old.data->>'sales_cost_expense_account_id'), '');

    if v_type is not distinct from v_old_type
       and v_currency is not distinct from v_old_currency
       and v_asset is not distinct from v_old_asset
       and v_expense is not distinct from v_old_expense then
      return new;
    end if;
  end if;

  perform public.erp_assert_account_type_currency(new.company_id, v_asset, 'asset', v_currency);
  perform public.erp_assert_account_type_currency(new.company_id, v_expense, 'expense', v_currency);
  new.data := new.data || jsonb_build_object(
    'inventoryAssetAccountId', v_asset,
    'inventory_asset_account_id', v_asset,
    'salesCostExpenseAccountId', v_expense,
    'sales_cost_expense_account_id', v_expense
  );
  return new;
end;
$$;

-- Normalize every historical car warehouse alias into the current pair.
update public.erp_cars
set data = data || jsonb_build_object(
  'warehouseId', coalesce(
    nullif(data->>'warehouseId',''),
    nullif(data->>'warehouse_id',''),
    nullif(data->>'currentWarehouseId',''),
    nullif(data->>'current_warehouse_id',''),
    nullif(data->>'lastWarehouseId',''),
    nullif(data->>'last_warehouse_id',''),
    nullif(data->>'warehouseCode',''),
    nullif(data->>'warehouseName','')
  ),
  'warehouse_id', coalesce(
    nullif(data->>'warehouseId',''),
    nullif(data->>'warehouse_id',''),
    nullif(data->>'currentWarehouseId',''),
    nullif(data->>'current_warehouse_id',''),
    nullif(data->>'lastWarehouseId',''),
    nullif(data->>'last_warehouse_id',''),
    nullif(data->>'warehouseCode',''),
    nullif(data->>'warehouseName','')
  )
)
where not is_deleted
  and coalesce(
    nullif(data->>'warehouseId',''), nullif(data->>'warehouse_id',''),
    nullif(data->>'currentWarehouseId',''), nullif(data->>'current_warehouse_id',''),
    nullif(data->>'lastWarehouseId',''), nullif(data->>'last_warehouse_id',''),
    nullif(data->>'warehouseCode',''), nullif(data->>'warehouseName','')
  ) is not null;

-- Avoid re-archiving a record while the explicit permanent-delete RPC runs.
create or replace function public.erp_capture_deleted_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb := to_jsonb(old);
  v_company uuid;
  v_record_id text;
begin
  if current_setting('qualityline.recycle_purge', true) = 'on' then
    return old;
  end if;
  if tg_table_name in ('erp_universal_recycle_bin','erp_records') then
    return old;
  end if;
  begin
    v_company := nullif(coalesce(v_payload->>'company_id', v_payload->>'companyId'), '')::uuid;
  exception when others then
    v_company := null;
  end;
  v_record_id := coalesce(v_payload->>'id', v_payload->>'record_id', v_payload->>'recordId');
  if v_record_id is null or trim(v_record_id) = '' then
    v_record_id := md5(v_payload::text || clock_timestamp()::text);
  end if;
  insert into public.erp_universal_recycle_bin(
    company_id, source_table, record_id, payload, deletion_mode, deleted_at, deleted_by
  ) values (
    v_company, tg_table_name, v_record_id, v_payload, 'hard', now(), auth.uid()
  );
  return old;
end;
$$;

-- Resolve the current ERP user and honor the per-user permission catalog
-- in database-side authorization, not only in the Flutter interface.
create or replace function public.erp_current_cloud_erp_user_id(p_company_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_slug text;
  v_local_user_id text;
  v_uid text := coalesce(auth.uid()::text, public.current_external_uid());
  v_email text := lower(coalesce(auth.jwt()->>'email',''));
  v_user_id text;
begin
  select c.slug, nullif(trim(m.local_user_id),'')
    into v_slug, v_local_user_id
  from public.company_memberships m
  join public.companies c on c.id=m.company_id
  where m.company_id=p_company_id
    and public.erp_membership_matches_current_user(m.user_id,m.user_uid)
    and m.is_active and c.is_active
  order by m.updated_at desc nulls last, m.created_at desc
  limit 1;

  if v_slug is null then
    return null;
  end if;

  select r.record_id into v_user_id
  from public.erp_records r
  where r.company_id=v_slug
    and r.entity_type='users'
    and r.deleted_at is null and not r.is_deleted
    and (
      (v_local_user_id is not null and r.record_id=v_local_user_id)
      or (v_uid is not null and r.payload->>'cloudAuthUid'=v_uid)
      or (v_email<>'' and lower(coalesce(r.payload->>'email',''))=v_email)
    )
  order by case
    when v_local_user_id is not null and r.record_id=v_local_user_id then 0
    when v_uid is not null and r.payload->>'cloudAuthUid'=v_uid then 1
    else 2 end,
    r.updated_at desc
  limit 1;

  return coalesce(v_user_id,v_local_user_id,v_uid);
end;
$$;

create or replace function public.erp_cloud_user_has_permission(
  p_company_id uuid,
  p_permission_code text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_slug text;
  v_user_id text;
  v_role_id text;
  v_has_override boolean := false;
begin
  if p_company_id is null
     or trim(coalesce(p_permission_code,''))=''
     or not public.is_company_member(p_company_id) then
    return false;
  end if;

  if public.is_company_admin(p_company_id)
     or public.erp_has_permission(p_company_id,trim(p_permission_code)) then
    return true;
  end if;

  select slug into v_slug from public.companies where id=p_company_id and is_active limit 1;
  v_user_id := public.erp_current_cloud_erp_user_id(p_company_id);
  if v_slug is null or v_user_id is null then
    return false;
  end if;

  select exists(
    select 1 from public.erp_records r
    where r.company_id=v_slug
      and r.entity_type='user_permission_overrides'
      and r.record_id=v_user_id
      and r.deleted_at is null and not r.is_deleted
      and coalesce((r.payload->>'enabled')::boolean,true)
  ) into v_has_override;

  if v_has_override then
    return exists(
      select 1
      from public.erp_records up
      join public.erp_records p
        on p.company_id=v_slug
       and p.entity_type='permissions'
       and p.record_id=up.payload->>'permissionId'
       and p.deleted_at is null and not p.is_deleted
      where up.company_id=v_slug
        and up.entity_type='user_permissions'
        and up.payload->>'userId'=v_user_id
        and up.deleted_at is null and not up.is_deleted
        and p.payload->>'code'=trim(p_permission_code)
    );
  end if;

  select payload->>'roleId' into v_role_id
  from public.erp_records
  where company_id=v_slug and entity_type='users' and record_id=v_user_id
    and deleted_at is null and not is_deleted
  limit 1;

  return exists(
    select 1
    from public.erp_records rp
    join public.erp_records p
      on p.company_id=v_slug
     and p.entity_type='permissions'
     and p.record_id=rp.payload->>'permissionId'
     and p.deleted_at is null and not p.is_deleted
    where rp.company_id=v_slug
      and rp.entity_type='role_permissions'
      and rp.payload->>'roleId'=v_role_id
      and rp.deleted_at is null and not rp.is_deleted
      and p.payload->>'code'=trim(p_permission_code)
  );
end;
$$;

create or replace function public.erp_recycle_bin_purge(
  p_company_id uuid,
  p_entity_type text,
  p_record_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
  v_archive public.erp_universal_recycle_bin%rowtype;
  v_pk text;
  v_has_company_id boolean := false;
  v_has_company_camel boolean := false;
begin
  if not public.is_company_member(p_company_id) then
    raise exception 'access_denied';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id, 'settings.recycle_bin.purge') then
    raise exception 'permanent_delete_permission_required';
  end if;

  delete from public.erp_records
  where company_id = p_company_id::text
    and entity_type = trim(p_entity_type)
    and record_id = trim(p_record_id)
    and deleted_at is not null;
  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    select * into v_archive
    from public.erp_universal_recycle_bin
    where source_table = trim(p_entity_type)
      and record_id = trim(p_record_id)
      and (company_id = p_company_id or company_id is null)
      and restored_at is null and purged_at is null
    order by deleted_at desc
    limit 1
    for update;

    if not found then
      raise exception 'deleted_record_not_found';
    end if;

    select case
      when exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_archive.source_table and column_name='id') then 'id'
      when exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_archive.source_table and column_name='record_id') then 'record_id'
      else null
    end into v_pk;

    select exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_archive.source_table and column_name='company_id') into v_has_company_id;
    select exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_archive.source_table and column_name='companyId') into v_has_company_camel;

    perform set_config('qualityline.recycle_purge','on',true);
    if to_regclass(format('public.%I',v_archive.source_table)) is not null and v_pk is not null then
      if v_has_company_id then
        execute format('delete from public.%I where %I::text=$1 and company_id::text=$2',v_archive.source_table,v_pk)
          using trim(p_record_id),p_company_id::text;
      elsif v_has_company_camel then
        execute format('delete from public.%I where %I::text=$1 and "companyId"::text=$2',v_archive.source_table,v_pk)
          using trim(p_record_id),p_company_id::text;
      else
        execute format('delete from public.%I where %I::text=$1',v_archive.source_table,v_pk)
          using trim(p_record_id);
      end if;
    end if;

    delete from public.erp_universal_recycle_bin where id=v_archive.id;
    v_deleted := 1;
  end if;

  return jsonb_build_object(
    'purged', v_deleted > 0,
    'entityType', trim(p_entity_type),
    'recordId', trim(p_record_id),
    'deletedRows', v_deleted
  );
end;
$$;

-- Create missing catalog permissions lazily so the complete Flutter catalog is
-- selectable even when a company was created before a permission was added.
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
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin
     and not public.erp_cloud_user_has_permission(v_company,'permissions.scopes.manage')
     and not public.erp_cloud_user_has_permission(v_company,'users.update') then
    raise exception 'permission_denied';
  end if;

  insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
  values(v_slug,'user_permission_overrides',p_user_id,
    jsonb_build_object('userId',p_user_id,'enabled',true),false,null,now())
  on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=v_slug and entity_type='user_permissions'
    and payload->>'userId'=p_user_id and deleted_at is null;

  foreach v_code in array coalesce(p_permission_codes,array[]::text[]) loop
    v_code := trim(v_code);
    if v_code='' then continue; end if;
    select record_id into v_permission_id
    from public.erp_records
    where company_id=v_slug and entity_type='permissions'
      and payload->>'code'=v_code and deleted_at is null and not is_deleted
    limit 1;
    if v_permission_id is null then
      v_permission_id := 'perm-'||substr(md5(v_code),1,24);
      v_module := split_part(v_code,'.',1);
      insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
      values(v_slug,'permissions',v_permission_id,
        jsonb_build_object(
          'id',v_permission_id,'code',v_code,'name',v_code,
          'module',v_module,'description','صلاحية تشغيلية مخصصة'
        ),false,null,now())
      on conflict(company_id,entity_type,record_id) do update
        set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
    end if;
    insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
    values(v_slug,'user_permissions',p_user_id||'::'||v_permission_id,
      jsonb_build_object('userId',p_user_id,'permissionId',v_permission_id),false,null,now())
    on conflict(company_id,entity_type,record_id) do update
      set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
  end loop;
end;
$$;

create or replace function public.erp_clear_cloud_user_permissions(p_user_id text)
returns void
language plpgsql security definer set search_path=public
as $$
declare v_company uuid; v_slug text; v_admin boolean;
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin
     and not public.erp_cloud_user_has_permission(v_company,'permissions.scopes.manage')
     and not public.erp_cloud_user_has_permission(v_company,'users.update') then
    raise exception 'permission_denied';
  end if;
  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=v_slug and entity_type in ('user_permission_overrides','user_permissions')
    and (record_id=p_user_id or payload->>'userId'=p_user_id) and deleted_at is null;
end;
$$;

-- Human-readable commercial order names and linked references.
create or replace function public.erp_list_cloud_sales_workflow_orders(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'id',o.id::text,'documentType','salesOrder','documentTitle','أمر بيع','orderNumber',o.order_number,
  'customerId',o.customer_id,'customerName',coalesce(c.data->>'name',''),
  'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
  'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
  'deliveryId',d.id::text,'deliveryNumber',d.document_number,'deliveryStatus',d.status,
  'invoiceId',i.id::text,'invoiceNumber',i.document_number,'invoiceStatus',i.status,
  'invoiceRemaining',public.erp_try_numeric(i.payload->>'remainingAmount',0),
  'journalEntryId',j.id,'journalEntryNumber',j.data->>'entryNumber',
  'accountingReference',coalesce(j.data->>'referenceId',i.id::text,o.id::text)
 )
 from public.erp_sales_orders_cloud o
 left join public.erp_customers c on c.id=o.customer_id and c.company_id=o.company_id and not c.is_deleted
 left join lateral (select x.* from public.erp_commercial_workflow_documents x where x.company_id=o.company_id and x.module='sales' and x.document_type='delivery' and x.parent_id=o.id and not x.is_deleted order by x.created_at desc limit 1) d on true
 left join lateral (select x.* from public.erp_commercial_workflow_documents x where x.company_id=o.company_id and x.module='sales' and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted order by x.created_at desc limit 1) i on true
 left join lateral (select je.* from public.erp_journal_entries je where je.company_id=o.company_id and not je.is_deleted and (je.data->>'orderId'=o.id::text or je.data->>'referenceId' in (o.id::text,i.id::text,d.id::text)) order by je.created_at desc limit 1) j on true
 where o.company_id=p_company_id and not o.is_deleted and public.erp_is_company_member(p_company_id)
 order by o.created_at desc;
$$;

create or replace function public.erp_list_cloud_purchase_workflow_orders(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'id',o.id::text,'documentType','purchaseOrder','documentTitle','أمر شراء','orderNumber',o.order_number,
  'supplierId',o.supplier_id,'supplierName',coalesce(s.data->>'name',''),
  'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
  'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
  'receiptId',r.id::text,'receiptNumber',r.document_number,'receiptStatus',r.status,
  'invoiceId',i.id::text,'invoiceNumber',i.document_number,'invoiceStatus',i.status,
  'invoiceRemaining',public.erp_try_numeric(i.payload->>'remainingAmount',0),
  'journalEntryId',j.id,'journalEntryNumber',j.data->>'entryNumber',
  'accountingReference',coalesce(j.data->>'referenceId',i.id::text,o.id::text)
 )
 from public.erp_purchase_orders_cloud o
 left join public.erp_suppliers s on s.id=o.supplier_id and s.company_id=o.company_id and not s.is_deleted
 left join lateral (select x.* from public.erp_commercial_workflow_documents x where x.company_id=o.company_id and x.module='purchases' and x.document_type='receipt' and x.parent_id=o.id and not x.is_deleted order by x.created_at desc limit 1) r on true
 left join lateral (select x.* from public.erp_commercial_workflow_documents x where x.company_id=o.company_id and x.module='purchases' and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted order by x.created_at desc limit 1) i on true
 left join lateral (select je.* from public.erp_journal_entries je where je.company_id=o.company_id and not je.is_deleted and (je.data->>'orderId'=o.id::text or je.data->>'referenceId' in (o.id::text,i.id::text,r.id::text)) order by je.created_at desc limit 1) j on true
 where o.company_id=p_company_id and not o.is_deleted and public.erp_is_company_member(p_company_id)
 order by o.created_at desc;
$$;

revoke all on function public.erp_current_cloud_erp_user_id(uuid) from public,anon;
grant execute on function public.erp_current_cloud_erp_user_id(uuid) to authenticated;
revoke all on function public.erp_cloud_user_has_permission(uuid,text) from public,anon;
grant execute on function public.erp_cloud_user_has_permission(uuid,text) to authenticated;
revoke all on function public.erp_recycle_bin_purge(uuid,text,text) from public,anon;
grant execute on function public.erp_recycle_bin_purge(uuid,text,text) to authenticated;
revoke all on function public.erp_set_cloud_user_permissions(text,text[]) from public,anon;
grant execute on function public.erp_set_cloud_user_permissions(text,text[]) to authenticated;
revoke all on function public.erp_clear_cloud_user_permissions(text) from public,anon;
grant execute on function public.erp_clear_cloud_user_permissions(text) to authenticated;
grant execute on function public.erp_list_cloud_sales_workflow_orders(uuid) to authenticated;
grant execute on function public.erp_list_cloud_purchase_workflow_orders(uuid) to authenticated;

commit;
