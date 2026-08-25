begin;

-- R9: fixed-asset depreciation must honor the operator-selected operational
-- timestamp just like commercial, inventory and cash workflows. The historical
-- period table remains monthly/date based, while the generated journal keeps
-- the exact timestamp selected by the user.
create or replace function public.erp_post_fixed_asset_depreciation_at(
  p_company_id uuid,
  p_asset_id uuid,
  p_effective_at timestamptz default now()
)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  a public.erp_fixed_assets%rowtype;
  v_amount numeric;
  v_book numeric;
  v_entry jsonb;
  v_lines jsonb;
  v_entry_id text:=gen_random_uuid()::text;
  v_number text;
  v_effective timestamptz:=coalesce(p_effective_at,now());
  v_posting_date date;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'لا توجد صلاحية على الشركة';
  end if;
  perform public.erp_validate_operational_date(p_company_id,'accounting',v_effective);
  v_posting_date:=v_effective::date;

  select * into a
  from public.erp_fixed_assets
  where company_id=p_company_id and id=p_asset_id and not is_deleted
  for update;
  if not found or not coalesce(a.is_active,true) then
    raise exception 'الأصل غير موجود أو غير فعال';
  end if;
  if a.last_depreciation_date is not null
     and date_trunc('month',a.last_depreciation_date)=date_trunc('month',v_posting_date) then
    raise exception 'تم توليد إهلاك هذا الأصل للشهر المحدد مسبقاً';
  end if;
  if a.asset_account_id is null
     or a.accumulated_depreciation_account_id is null
     or a.depreciation_expense_account_id is null then
    raise exception 'حسابات الأصل المحاسبية غير مكتملة';
  end if;

  v_book:=greatest(a.acquisition_cost-coalesce(a.accumulated_depreciation,0),a.salvage_value);
  if v_book<=a.salvage_value then raise exception 'الأصل مهلك بالكامل'; end if;
  if a.depreciation_method='straight_line' then
    v_amount:=(a.acquisition_cost-a.salvage_value)/a.useful_life_months;
  else
    v_amount:=v_book*coalesce(a.declining_rate,2.0/a.useful_life_months);
  end if;
  v_amount:=round(least(v_amount,v_book-a.salvage_value),2);
  if v_amount<=0 then raise exception 'قيمة الإهلاك غير صحيحة'; end if;

  v_number:='DEP-'||a.asset_code||'-'||to_char(v_posting_date,'YYYYMM');
  v_entry:=jsonb_build_object(
    'id',v_entry_id,
    'entryNumber',v_number,
    'entryDate',v_effective,
    'effectiveAt',v_effective,
    'description','إهلاك الأصل: '||a.name,
    'referenceType','fixed_asset_depreciation',
    'referenceId',a.id::text,
    'currency',a.currency,
    'createdAt',v_effective
  );
  v_lines:=jsonb_build_array(
    jsonb_build_object(
      'id',gen_random_uuid()::text,'entryId',v_entry_id,
      'accountId',a.depreciation_expense_account_id,
      'debit',v_amount,'credit',0,
      'description','مصروف إهلاك '||a.name,'currency',a.currency),
    jsonb_build_object(
      'id',gen_random_uuid()::text,'entryId',v_entry_id,
      'accountId',a.accumulated_depreciation_account_id,
      'debit',0,'credit',v_amount,
      'description','مجمع إهلاك '||a.name,'currency',a.currency)
  );

  perform public.erp_post_cloud_manual_journal(p_company_id,v_entry,v_lines);
  insert into public.erp_asset_depreciation_entries(
    company_id,asset_id,period_date,opening_book_value,depreciation_amount,
    closing_book_value,journal_entry_id,depreciation_method)
  values(
    p_company_id,a.id,date_trunc('month',v_posting_date)::date,
    v_book,v_amount,v_book-v_amount,v_entry_id,a.depreciation_method
  );
  update public.erp_fixed_assets
  set accumulated_depreciation=coalesce(accumulated_depreciation,0)+v_amount,
      current_book_value=v_book-v_amount,
      last_depreciation_date=v_posting_date,
      updated_at=v_effective
  where id=a.id;

  return v_entry_id::uuid;
end $$;

revoke all on function public.erp_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) from public,anon;
grant execute on function public.erp_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) to authenticated,service_role;

commit;
