-- Quality Line ERP R79 stabilization for independent media permissions.
-- Keeps ordinary data edits independent from image permissions while preserving
-- fail-closed server enforcement for every actual image mutation.
begin;

create or replace function public.erp_r78_media_permission_guard()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company_id uuid;
  v_permission text;
  v_changed boolean:=true;
  v_old_media text:='';
  v_new_media text:='';
begin
  -- Trusted migrations/service-role writes have no end-user JWT. User-facing
  -- Edge Functions perform their own caller permission checks before those
  -- service-role writes.
  if auth.uid() is null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  -- R49's historical product-update implementation replaces image rows even
  -- when the byte-for-byte ordered image list is unchanged. The protected R79
  -- wrapper below enables this transaction-local bypass only after verifying
  -- that the requested image array exactly matches the persisted image array.
  if current_setting('qualityline.r79_verified_media_noop',true)='on' then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  if tg_op='DELETE' then v_company_id:=old.company_id;
  else v_company_id:=new.company_id;
  end if;

  case tg_table_name
    when 'erp_customers' then
      v_permission:='customers.image.update';
      if tg_op='INSERT' then
        v_new_media:=coalesce(new.data->>'photoBase64',new.data->>'photo_base64',new.data->>'photo','');
        v_changed:=btrim(v_new_media)<>'';
      elsif tg_op='UPDATE' then
        v_old_media:=coalesce(old.data->>'photoBase64',old.data->>'photo_base64',old.data->>'photo','');
        v_new_media:=coalesce(new.data->>'photoBase64',new.data->>'photo_base64',new.data->>'photo','');
        v_changed:=v_new_media is distinct from v_old_media;
      else
        v_changed:=false;
      end if;
    when 'erp_suppliers' then
      v_permission:='suppliers.image.update';
      if tg_op='INSERT' then
        v_new_media:=coalesce(new.data->>'photoBase64',new.data->>'photo_base64',new.data->>'photo','');
        v_changed:=btrim(v_new_media)<>'';
      elsif tg_op='UPDATE' then
        v_old_media:=coalesce(old.data->>'photoBase64',old.data->>'photo_base64',old.data->>'photo','');
        v_new_media:=coalesce(new.data->>'photoBase64',new.data->>'photo_base64',new.data->>'photo','');
        v_changed:=v_new_media is distinct from v_old_media;
      else
        v_changed:=false;
      end if;
    when 'erp_cars' then
      v_permission:='cars.images.manage';
      if tg_op='INSERT' then
        v_new_media:=coalesce(new.data->>'imageBase64',new.data->>'image_base64',new.data->>'photoBase64','');
        v_changed:=btrim(v_new_media)<>'';
      elsif tg_op='UPDATE' then
        v_old_media:=coalesce(old.data->>'imageBase64',old.data->>'image_base64',old.data->>'photoBase64','');
        v_new_media:=coalesce(new.data->>'imageBase64',new.data->>'image_base64',new.data->>'photoBase64','');
        v_changed:=v_new_media is distinct from v_old_media;
      else
        v_changed:=false;
      end if;
    when 'erp_inventory' then
      v_permission:='inventory.images.manage';
      if tg_op='INSERT' then
        v_new_media:=coalesce(new.data->>'imageBase64',new.data->>'image_base64',new.data->>'image','');
        v_changed:=btrim(v_new_media)<>'';
      elsif tg_op='UPDATE' then
        v_old_media:=coalesce(old.data->>'imageBase64',old.data->>'image_base64',old.data->>'image','');
        v_new_media:=coalesce(new.data->>'imageBase64',new.data->>'image_base64',new.data->>'image','');
        v_changed:=v_new_media is distinct from v_old_media;
      else
        v_changed:=false;
      end if;
    when 'erp_car_images' then
      v_permission:='cars.images.manage';
      if tg_op='INSERT' or tg_op='DELETE' then
        v_changed:=true;
      else
        v_changed:=new.data is distinct from old.data
          or new.is_deleted is distinct from old.is_deleted
          or new.deleted_at is distinct from old.deleted_at;
      end if;
    when 'erp_product_images' then
      v_permission:='inventory.images.manage';
      if tg_op='INSERT' or tg_op='DELETE' then
        v_changed:=true;
      else
        v_changed:=new.data is distinct from old.data
          or new.is_deleted is distinct from old.is_deleted
          or new.deleted_at is distinct from old.deleted_at;
      end if;
    else
      if tg_op='DELETE' then return old; else return new; end if;
  end case;

  if v_changed and not public.erp_cloud_user_has_permission(v_company_id,v_permission) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;

  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.erp_r78_media_permission_guard() from public,anon,authenticated;

-- Recreate media triggers so installations that applied R78 use this stabilized
-- implementation without depending on trigger creation order.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'erp_customers','erp_suppliers','erp_cars','erp_inventory',
    'erp_car_images','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format('drop trigger if exists zz_r78_media_permission_guard on public.%I',v_table);
      execute format(
        'create trigger zz_r78_media_permission_guard before insert or update or delete on public.%I '
        'for each row execute function public.erp_r78_media_permission_guard()',
        v_table
      );
    end if;
  end loop;
end $$;

-- The historical R49 product RPC always rewrites the full image collection.
-- Compare the requested ordered image list with PostgreSQL first. A true image
-- mutation requires inventory.images.manage. An identical list is allowed as a
-- transaction-local no-op so inventory.update remains independent.
create or replace function public.erp_r49_update_inventory_product(
  p_company_id uuid,
  p_product_id text,
  p_product jsonb,
  p_images jsonb default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_requested jsonb:=coalesce(p_images,'[]'::jsonb);
  v_current jsonb:='[]'::jsonb;
  v_media_changed boolean:=false;
  v_can_manage_media boolean:=false;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.update') then
    raise exception 'permission_denied:inventory.update' using errcode='42501';
  end if;

  if jsonb_typeof(v_requested)<>'array' then
    raise exception 'invalid_product_images' using errcode='22023';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(coalesce(i.data->>'imageBase64',i.data->>'image_base64',''))
      order by public.erp_try_numeric(coalesce(i.data->>'sortOrder',i.data->>'sort_order'),0),i.created_at,i.id),
    '[]'::jsonb
  ) into v_current
  from public.erp_product_images i
  where i.company_id=p_company_id
    and not i.is_deleted
    and coalesce(i.data->>'productId',i.data->>'product_id')=p_product_id;

  v_media_changed:=v_requested is distinct from coalesce(v_current,'[]'::jsonb);
  v_can_manage_media:=public.is_company_admin(p_company_id)
    or public.erp_cloud_user_has_permission(p_company_id,'inventory.images.manage');

  if v_media_changed and not v_can_manage_media then
    raise exception 'permission_denied:inventory.images.manage' using errcode='42501';
  end if;

  if not v_media_changed and not v_can_manage_media then
    perform set_config('qualityline.r79_verified_media_noop','on',true);
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.update',true);

  begin
    perform public.erp_update_inventory_product(
      p_company_id,p_product_id,p_product,v_requested
    );
  exception when others then
    perform set_config('qualityline.r49_master_permission','',true);
    perform set_config('qualityline.r79_verified_media_noop','',true);
    raise;
  end;

  perform set_config('qualityline.r49_master_permission','',true);
  perform set_config('qualityline.r79_verified_media_noop','',true);
end;
$$;
revoke all on function public.erp_r49_update_inventory_product(uuid,text,jsonb,jsonb)
  from public,anon;
grant execute on function public.erp_r49_update_inventory_product(uuid,text,jsonb,jsonb)
  to authenticated,service_role;

-- Make create semantics explicit too: adding product images is a separate
-- privilege from creating the product master itself.
create or replace function public.erp_r49_create_inventory_product(
  p_company_id uuid,p_product_id text,p_product jsonb,p_warehouse_id text,
  p_opening_quantity integer,p_images jsonb,p_user_name text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_images jsonb:=coalesce(p_images,'[]'::jsonb);
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.create') then
    raise exception 'permission_denied:inventory.create' using errcode='42501';
  end if;
  if jsonb_typeof(v_images)<>'array' then
    raise exception 'invalid_product_images' using errcode='22023';
  end if;
  if jsonb_array_length(v_images)>0
     and not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.images.manage') then
    raise exception 'permission_denied:inventory.images.manage' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.create',true);
  begin
    perform public.erp_create_inventory_product(
      p_company_id,p_product_id,p_product,p_warehouse_id,p_opening_quantity,v_images,p_user_name
    );
  exception when others then
    perform set_config('qualityline.r49_master_permission','',true);
    raise;
  end;
  perform set_config('qualityline.r49_master_permission','',true);
end;
$$;
revoke all on function public.erp_r49_create_inventory_product(uuid,text,jsonb,text,integer,jsonb,text)
  from public,anon;
grant execute on function public.erp_r49_create_inventory_product(uuid,text,jsonb,text,integer,jsonb,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
