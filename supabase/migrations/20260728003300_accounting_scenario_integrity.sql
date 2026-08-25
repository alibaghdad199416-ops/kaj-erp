-- Scenario-driven accounting integrity hardening.
-- Enforces journal date/currency/line rules at the authoritative database layer
-- and protects account classifications already used by posted activity.
begin;

create or replace function public.erp_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=p_account->>'id';
  v_parent text:=nullif(p_account->>'parentId','');
  v_currency text:=upper(coalesce(nullif(p_account->>'currency',''),'USD'));
  v_type text:=lower(coalesce(p_account->>'type',''));
  v_parent_currency text;
  v_existing_currency text;
  v_existing_type text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(trim(p_account->>'code'),'')='' or coalesce(trim(p_account->>'name'),'')='' then raise exception 'بيانات الحساب غير مكتملة'; end if;
  if v_type not in ('asset','liability','equity','revenue','expense') then raise exception 'نوع الحساب غير صحيح'; end if;
  if coalesce(v_currency,'')='' then raise exception 'عملة الحساب مطلوبة'; end if;

  select upper(currency),account_type into v_existing_currency,v_existing_type
  from public.erp_accounts where organization_id=p_company_id and account_id=v_id;
  if p_require_existing and v_existing_currency is null then raise exception 'الحساب غير موجود'; end if;
  if p_require_existing and (v_existing_currency<>v_currency or v_existing_type<>v_type) and exists(
    select 1 from public.erp_journal_lines
    where company_id=p_company_id and not is_deleted and data->>'accountId'=v_id
  ) then raise exception 'لا يمكن تغيير نوع أو عملة حساب مرتبط بقيود'; end if;

  if exists(select 1 from public.erp_accounts where organization_id=p_company_id and lower(code)=lower(trim(p_account->>'code')) and account_id<>v_id and is_active) then raise exception 'رمز الحساب مستخدم مسبقًا'; end if;
  if v_parent=v_id then raise exception 'لا يمكن جعل الحساب أباً لنفسه'; end if;
  if v_parent is not null then
    select upper(currency) into v_parent_currency from public.erp_accounts where organization_id=p_company_id and account_id=v_parent and is_active;
    if v_parent_currency is null then raise exception 'الحساب الأب غير موجود أو غير فعال'; end if;
    if v_parent_currency<>v_currency then raise exception 'عملة الحساب الفرعي يجب أن تطابق عملة الحساب الأب'; end if;
    if p_require_existing and exists(
      with recursive descendants as (
        select account_id from public.erp_accounts where organization_id=p_company_id and parent_account_id=v_id and is_active
        union all
        select a.account_id from public.erp_accounts a join descendants d on a.parent_account_id=d.account_id
        where a.organization_id=p_company_id and a.is_active
      ) select 1 from descendants where account_id=v_parent
    ) then raise exception 'لا يمكن نقل الحساب تحت أحد حساباته الفرعية'; end if;
  end if;

  insert into public.erp_accounts(organization_id,account_id,code,name,account_type,parent_account_id,currency,opening_balance,is_active,source_updated_at,synced_at,synced_by)
  values(p_company_id,v_id,trim(p_account->>'code'),trim(p_account->>'name'),v_type,v_parent,v_currency,coalesce((p_account->>'openingBalance')::numeric,0),coalesce((p_account->>'isActive')::boolean,true),now(),now(),auth.uid())
  on conflict(organization_id,account_id) do update set code=excluded.code,name=excluded.name,account_type=excluded.account_type,parent_account_id=excluded.parent_account_id,currency=excluded.currency,opening_balance=excluded.opening_balance,is_active=excluded.is_active,source_updated_at=now(),synced_at=now(),synced_by=auth.uid();
end $$;

create or replace function public.erp_post_cloud_manual_journal(p_company_id uuid,p_entry jsonb,p_lines jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=p_entry->>'id';
  v_line jsonb;
  v_debit numeric:=0;
  v_credit numeric:=0;
  v_line_debit numeric;
  v_line_credit numeric;
  v_period public.erp_fiscal_periods%rowtype;
  v_date timestamptz;
  v_currency text:=upper(coalesce(p_entry->>'currency',''));
  v_account_currency text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  begin v_date:=nullif(p_entry->>'entryDate','')::timestamptz; exception when others then raise exception 'تاريخ القيد غير صحيح'; end;
  if coalesce(v_id,'')='' or coalesce(trim(p_entry->>'entryNumber'),'')='' or coalesce(trim(p_entry->>'description'),'')='' or v_date is null or v_currency='' or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 then raise exception 'بيانات القيد غير مكتملة'; end if;
  if exists(select 1 from public.erp_journal_entries where company_id=p_company_id and not is_deleted and lower(data->>'entryNumber')=lower(trim(p_entry->>'entryNumber'))) then raise exception 'رقم القيد مستخدم مسبقًا'; end if;

  select * into v_period from public.erp_fiscal_periods
  where company_id=p_company_id and not is_deleted and data->>'status'='open'
    and v_date between (data->>'startDate')::timestamptz and (data->>'endDate')::timestamptz
  order by (data->>'startDate')::timestamptz desc limit 1;
  if exists(select 1 from public.erp_fiscal_periods where company_id=p_company_id and not is_deleted) and v_period.id is null then raise exception 'لا توجد فترة مالية مفتوحة لتاريخ القيد'; end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if coalesce(v_line->>'id','')='' or v_line->>'entryId'<>v_id or coalesce(v_line->>'accountId','')='' then raise exception 'سطر غير مرتبط بالقيد أو بياناته ناقصة'; end if;
    begin
      v_line_debit:=coalesce(nullif(v_line->>'debit','')::numeric,0);
      v_line_credit:=coalesce(nullif(v_line->>'credit','')::numeric,0);
    exception when others then raise exception 'قيم سطر القيد غير رقمية'; end;
    if v_line_debit<0 or v_line_credit<0 or (v_line_debit>0 and v_line_credit>0) or (v_line_debit=0 and v_line_credit=0) then raise exception 'يجب أن يحتوي سطر القيد على مدين أو دائن موجب واحد فقط'; end if;
    select upper(currency) into v_account_currency from public.erp_accounts
    where organization_id=p_company_id and account_id=v_line->>'accountId' and is_active;
    if v_account_currency is null then raise exception 'أحد حسابات القيد غير موجود أو غير فعال'; end if;
    if v_account_currency not in (v_currency,'MULTI') then raise exception 'عملة حساب السطر لا تطابق عملة القيد'; end if;
    v_debit:=v_debit+v_line_debit;
    v_credit:=v_credit+v_line_credit;
  end loop;
  if abs(v_debit-v_credit)>0.01 or v_debit<=0 then raise exception 'القيد غير متوازن'; end if;

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,p_entry||jsonb_build_object('currency',v_currency,'totalDebit',v_debit,'totalCredit',v_credit,'status','posted','fiscalPeriodId',v_period.id,'fiscalYearId',v_period.data->>'fiscalYearId'),auth.uid(),auth.uid());
  for v_line in select value from jsonb_array_elements(p_lines) loop
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_line->>'id',v_line,auth.uid(),auth.uid());
  end loop;
end $$;

grant execute on function public.erp_save_cloud_ledger_account(uuid,jsonb,boolean) to authenticated;
grant execute on function public.erp_post_cloud_manual_journal(uuid,jsonb,jsonb) to authenticated;

commit;
