-- Quality Line ERP R80: scope the verified product-image no-op bypass to the
-- product image table only. All master-data media fields remain independently
-- protected even while the historical R49 product image rewrite is executing.
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
  if auth.uid() is null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  -- Only erp_product_images may use the transaction-local no-op bypass. The
  -- erp_inventory master row and every other media table still execute their
  -- normal permission comparison, preventing a crafted p_product payload from
  -- changing imageBase64 without inventory.images.manage.
  if tg_table_name='erp_product_images'
     and current_setting('qualityline.r79_verified_media_noop',true)='on' then
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

notify pgrst,'reload schema';
commit;
