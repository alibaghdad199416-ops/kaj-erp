-- R26 runtime data/UI contract closure
begin;

-- The incoming selected ledger is authoritative when the user may edit it.
-- Canonicalize both spellings before the low-level save so a legacy alias
-- cannot win again after refresh.
create or replace function public.erp_r9_save_cloud_cash_account(p_company_id uuid,p_account jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_old jsonb;
  v_guarded jsonb;
  v_id text:=coalesce(p_account->>'id','');
  v_ledger text;
  v_can_edit_ledger boolean;
begin
  select data into v_old from public.erp_cash_accounts
   where company_id=p_company_id and id=v_id and not is_deleted;
  if v_old is null then
    perform public.erp_r9_require_field_edit(p_company_id,'cashbox','name','accounting.create');
  elsif not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then
    raise exception 'permission_denied:accounting.update' using errcode='42501';
  end if;

  v_guarded:=public.erp_r24_guard_cash_account_payload(
    p_company_id,coalesce(v_old,'{}'::jsonb),p_account
  );
  v_can_edit_ledger:=public.erp_cloud_user_can_edit_field(
    p_company_id,'cashbox','ledgerAccount',null
  );

  if v_can_edit_ledger then
    v_ledger:=nullif(btrim(coalesce(
      nullif(p_account->>'account_id',''),
      nullif(p_account->>'accountId',''),
      nullif(v_guarded->>'account_id',''),
      nullif(v_guarded->>'accountId','')
    )), '');
  else
    v_ledger:=nullif(btrim(coalesce(
      nullif(v_guarded->>'account_id',''),
      nullif(v_guarded->>'accountId','')
    )), '');
  end if;

  if v_ledger is not null then
    if exists(
      select 1 from public.erp_cash_accounts x
      where x.company_id=p_company_id and x.id<>v_id and not x.is_deleted
        and public.erp_r23_cashbox_ledger_account_id(x.data)=v_ledger
    ) then
      raise exception 'cashbox_ledger_account_already_bound:%',v_ledger using errcode='23505';
    end if;
    v_guarded:=v_guarded||jsonb_build_object(
      'accountId',v_ledger,'account_id',v_ledger
    );
  end if;

  perform public.erp_save_cloud_cash_account(p_company_id,v_guarded);
end $$;

-- Make the R22 public endpoint explicitly converge on the canonical saver.
create or replace function public.erp_r22_save_cloud_cash_account(
  p_company_id uuid,p_account jsonb
) returns void language sql security definer set search_path=public as $$
  select public.erp_r9_save_cloud_cash_account($1,$2)
$$;

-- Avoid reading the entire image master table for every visible car card.
create or replace function public.erp_r26_list_car_images_for_car(
  p_company_id uuid,p_car_id text
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_readable_master_json(
      p_company_id,'erp_car_images',
      case when jsonb_typeof(i.data)='object' then i.data else '{}'::jsonb end
    ) || jsonb_build_object(
      'id',i.id,'_cloudVersion',i.version,'_cloudUpdatedAt',i.updated_at
    )
  from public.erp_car_images i
  where i.company_id=p_company_id
    and not i.is_deleted
    and coalesce(i.data->>'carId',i.data->>'car_id')=p_car_id
    and not public.erp_r15_pending_delete_exists(p_company_id,'erp_car_images',i.id)
    and public.is_active_company_member(p_company_id)
    and (
      public.erp_cloud_user_has_permission(p_company_id,'cars.view')
      or public.is_company_admin(p_company_id)
    )
  order by public.erp_try_numeric(coalesce(i.data->>'sortOrder',i.data->>'sort_order'),0),i.created_at,i.id
$$;

grant execute on function public.erp_r22_save_cloud_cash_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r26_list_car_images_for_car(uuid,text) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
