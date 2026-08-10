begin;

-- V6.7/V6.8: fixed and non-current assets can be removed together with every
-- direct operational link. The operation remains a tenant-scoped soft delete
-- and preserves the complete package in the universal recycle bin.

alter table public.erp_fixed_assets
  add column if not exists deleted_by uuid,
  add column if not exists deleted_reason text;

alter table public.erp_asset_depreciation_entries
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid,
  add column if not exists deleted_reason text,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists erp_asset_depreciation_active_asset_idx
  on public.erp_asset_depreciation_entries(company_id,asset_id,period_date desc)
  where not is_deleted;

create or replace function public.erp_delete_fixed_asset(
  p_company_id uuid,
  p_asset_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_asset public.erp_fixed_assets%rowtype;
  v_link record;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Delete fixed asset and every linked record');
  v_now timestamptz:=now();
  v_batch uuid:=gen_random_uuid();
  v_depreciation_count integer:=0;
  v_journal_count integer:=0;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );
  select fa.* into v_asset
  from public.erp_fixed_assets as fa
  where fa.company_id=p_company_id and fa.id=p_asset_id
  for update;
  if not found or v_asset.is_deleted then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_fixed_assets',true);
  perform set_config('qualityline.deletion_root_id',p_asset_id::text,true);
  perform set_config('qualityline.deletion_reason',v_reason,true);

  for v_link in
    select de.id,de.journal_entry_id
    from public.erp_asset_depreciation_entries as de
    where de.company_id=p_company_id
      and de.asset_id=p_asset_id
      and not de.is_deleted
    order by de.period_date desc,de.id desc
    for update
  loop
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_link.journal_entry_id,v_reason
    );
    if nullif(btrim(coalesce(v_link.journal_entry_id,'')),'') is not null then
      v_journal_count:=v_journal_count+1;
    end if;
    update public.erp_asset_depreciation_entries as de
       set is_deleted=true,
           deleted_at=v_now,
           deleted_by=auth.uid(),
           deleted_reason=v_reason,
           updated_at=v_now
     where de.company_id=p_company_id and de.id=v_link.id;
    v_depreciation_count:=v_depreciation_count+1;
  end loop;

  -- Delete every journal that explicitly identifies this asset, including
  -- acquisition, adjustment, depreciation, revaluation, and disposal links.
  -- Depreciation journals already removed above are skipped by not is_deleted.
  for v_link in
    select je.id
    from public.erp_journal_entries as je
    where je.company_id=p_company_id
      and not je.is_deleted
      and coalesce(
        je.data->>'fixedAssetId',je.data->>'fixed_asset_id',
        je.data->>'assetId',je.data->>'asset_id',
        je.data->>'referenceId',je.data->>'reference_id'
      )=p_asset_id::text
      and lower(coalesce(je.data->>'referenceType',je.data->>'reference_type','fixed_asset')) in (
        'fixed_asset','fixed asset','asset','non_current_asset','non-current asset',
        'fixed_asset_acquisition','fixed_asset_adjustment','fixed_asset_revaluation',
        'fixed_asset_depreciation','fixed_asset_disposal','asset_acquisition',
        'asset_adjustment','asset_revaluation','asset_depreciation','asset_disposal'
      )
    for update
  loop
    perform public.erp_v65_soft_delete_journal(p_company_id,v_link.id,v_reason);
    v_journal_count:=v_journal_count+1;
  end loop;

  update public.erp_fixed_assets as fa
     set is_deleted=true,
         deleted_at=v_now,
         deleted_by=auth.uid(),
         deleted_reason=v_reason,
         is_active=false,
         status='deleted',
         updated_at=v_now
   where fa.company_id=p_company_id and fa.id=p_asset_id and not fa.is_deleted;

  update public.erp_universal_recycle_bin
     set relation_context=relation_context||jsonb_build_object(
       'fixedAssetCode',coalesce(v_asset.asset_code,v_asset.asset_number),
       'fixedAssetName',coalesce(v_asset.name,v_asset.name_ar),
       'depreciationEntriesDeleted',v_depreciation_count,
       'linkedJournalsDeleted',v_journal_count,
       'allDirectAssetLinksDeleted',true
     )
   where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

revoke all on function public.erp_delete_fixed_asset(uuid,uuid,text) from public,anon;
grant execute on function public.erp_delete_fixed_asset(uuid,uuid,text) to authenticated,service_role;

commit;
