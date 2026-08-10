begin;

create table if not exists public.erp_fiscal_years (like public.erp_cars including all);
create table if not exists public.erp_fiscal_periods (like public.erp_cars including all);
create table if not exists public.erp_fiscal_period_events (like public.erp_cars including all);

create unique index if not exists erp_journal_entry_number_uq
  on public.erp_journal_entries(company_id, lower(data->>'entryNumber')) where not is_deleted;
create index if not exists erp_journal_entry_date_idx
  on public.erp_journal_entries(company_id, (data->>'entryDate')) where not is_deleted;
create index if not exists erp_fiscal_period_dates_idx
  on public.erp_fiscal_periods(company_id, (data->>'startDate'), (data->>'endDate')) where not is_deleted;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['erp_fiscal_years','erp_fiscal_periods','erp_fiscal_period_events'] LOOP
    EXECUTE format('alter table public.%I enable row level security',t);
    EXECUTE format('drop policy if exists %I on public.%I',t||'_tenant',t);
    EXECUTE format('create policy %I on public.%I for all to authenticated using (public.is_active_company_member(company_id)) with check (public.is_active_company_member(company_id))',t||'_tenant',t);
    EXECUTE format('grant select on public.%I to authenticated',t);
  END LOOP;
END $$;

create or replace function public.erp_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_account->>'id'; v_parent text:=nullif(p_account->>'parentId','');
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(trim(p_account->>'code'),'')='' or coalesce(trim(p_account->>'name'),'')='' then raise exception 'بيانات الحساب غير مكتملة'; end if;
  if p_require_existing and not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_id) then raise exception 'الحساب غير موجود'; end if;
  if v_parent is not null and not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_parent and is_active) then raise exception 'الحساب الأب غير موجود أو غير فعال'; end if;
  insert into public.erp_accounts(organization_id,account_id,code,name,account_type,parent_account_id,currency,opening_balance,is_active,source_updated_at,synced_at,synced_by)
  values(p_company_id,v_id,trim(p_account->>'code'),trim(p_account->>'name'),p_account->>'type',v_parent,coalesce(nullif(p_account->>'currency',''),'USD'),coalesce((p_account->>'openingBalance')::numeric,0),coalesce((p_account->>'isActive')::boolean,true),now(),now(),auth.uid())
  on conflict(organization_id,account_id) do update set code=excluded.code,name=excluded.name,account_type=excluded.account_type,parent_account_id=excluded.parent_account_id,currency=excluded.currency,opening_balance=excluded.opening_balance,is_active=excluded.is_active,source_updated_at=now(),synced_at=now(),synced_by=auth.uid();
end $$;

create or replace function public.erp_delete_cloud_ledger_account(p_company_id uuid,p_account_id text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  perform 1 from public.erp_accounts where organization_id=p_company_id and account_id=p_account_id for update;
  if not found then raise exception 'الحساب غير موجود'; end if;
  if exists(select 1 from public.erp_accounts where organization_id=p_company_id and parent_account_id=p_account_id and is_active) then raise exception 'لا يمكن حذف حساب يحتوي على حسابات فرعية'; end if;
  if exists(select 1 from public.erp_journal_lines where company_id=p_company_id and not is_deleted and data->>'accountId'=p_account_id) then raise exception 'لا يمكن حذف حساب مرتبط بقيود يومية'; end if;
  if exists(select 1 from public.erp_cash_accounts where company_id=p_company_id and not is_deleted and data->>'accountId'=p_account_id) then raise exception 'لا يمكن حذف حساب مرتبط بصندوق مالي'; end if;
  update public.erp_accounts set is_active=false,source_updated_at=now(),synced_at=now(),synced_by=auth.uid() where organization_id=p_company_id and account_id=p_account_id;
end $$;

create or replace function public.erp_post_cloud_manual_journal(p_company_id uuid,p_entry jsonb,p_lines jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_entry->>'id'; v_line jsonb; v_debit numeric:=0; v_credit numeric:=0; v_period public.erp_fiscal_periods%rowtype; v_date timestamptz:=nullif(p_entry->>'entryDate','')::timestamptz;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(trim(p_entry->>'entryNumber'),'')='' or jsonb_array_length(coalesce(p_lines,'[]'))<2 then raise exception 'بيانات القيد غير مكتملة'; end if;
  if exists(select 1 from public.erp_journal_entries where company_id=p_company_id and not is_deleted and lower(data->>'entryNumber')=lower(p_entry->>'entryNumber')) then raise exception 'رقم القيد مستخدم مسبقًا'; end if;
  select * into v_period from public.erp_fiscal_periods where company_id=p_company_id and not is_deleted and data->>'status'='open' and v_date between (data->>'startDate')::timestamptz and (data->>'endDate')::timestamptz limit 1;
  if exists(select 1 from public.erp_fiscal_periods where company_id=p_company_id and not is_deleted) and v_period.id is null then raise exception 'لا توجد فترة مالية مفتوحة لتاريخ القيد'; end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    if v_line->>'entryId'<>v_id then raise exception 'سطر غير مرتبط بالقيد'; end if;
    if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_line->>'accountId' and is_active) then raise exception 'أحد حسابات القيد غير موجود أو غير فعال'; end if;
    if coalesce((v_line->>'debit')::numeric,0)<0 or coalesce((v_line->>'credit')::numeric,0)<0 or (coalesce((v_line->>'debit')::numeric,0)>0 and coalesce((v_line->>'credit')::numeric,0)>0) then raise exception 'قيم سطر القيد غير صحيحة'; end if;
    v_debit:=v_debit+coalesce((v_line->>'debit')::numeric,0); v_credit:=v_credit+coalesce((v_line->>'credit')::numeric,0);
  end loop;
  if abs(v_debit-v_credit)>0.01 or v_debit<=0 then raise exception 'القيد غير متوازن'; end if;
  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by) values(p_company_id,v_id,p_entry||jsonb_build_object('totalDebit',v_debit,'totalCredit',v_credit,'status','posted','fiscalPeriodId',v_period.id,'fiscalYearId',v_period.data->>'fiscalYearId'),auth.uid(),auth.uid());
  for v_line in select value from jsonb_array_elements(p_lines) loop
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values(p_company_id,v_line->>'id',v_line,auth.uid(),auth.uid());
  end loop;
end $$;

create or replace function public.erp_delete_cloud_manual_journal(p_company_id uuid,p_entry_id text)
returns void language plpgsql security definer set search_path=public as $$
declare v_ref text; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select data->>'referenceType' into v_ref from public.erp_journal_entries where company_id=p_company_id and id=p_entry_id and not is_deleted for update;
  if not found then raise exception 'لم يتم العثور على القيد المطلوب'; end if;
  if coalesce(v_ref,'manual') not in ('manual','manual_journal','') then raise exception 'لا يمكن حذف قيد مولد تلقائيًا من دفتر اليومية'; end if;
  update public.erp_journal_entries set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid() where company_id=p_company_id and id=p_entry_id;
  update public.erp_journal_lines set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid() where company_id=p_company_id and data->>'entryId'=p_entry_id;
end $$;

create or replace function public.erp_cloud_account_statement(p_company_id uuid,p_account_id text,p_from_date timestamptz,p_to_date timestamptz)
returns table("entryId" text,"entryNumber" text,"entryDate" text,"entryDescription" text,currency text,"lineDescription" text,debit numeric,credit numeric)
language sql security definer set search_path=public as $$
 select je.id,je.data->>'entryNumber',je.data->>'entryDate',je.data->>'description',je.data->>'currency',jl.data->>'description',coalesce((jl.data->>'debit')::numeric,0),coalesce((jl.data->>'credit')::numeric,0)
 from public.erp_journal_lines jl join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
 where jl.company_id=p_company_id and public.is_active_company_member(p_company_id) and not jl.is_deleted and not je.is_deleted and je.data->>'status'='posted' and jl.data->>'accountId'=p_account_id and (je.data->>'entryDate')::timestamptz between p_from_date and p_to_date
 order by (je.data->>'entryDate')::timestamptz,je.created_at,jl.created_at;
$$;

create or replace function public.erp_cloud_trial_balance(p_company_id uuid,p_currency text)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object('debit',coalesce(sum((jl.data->>'debit')::numeric),0),'credit',coalesce(sum((jl.data->>'credit')::numeric),0))
 from public.erp_journal_lines jl join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
 where jl.company_id=p_company_id and public.is_active_company_member(p_company_id) and not jl.is_deleted and not je.is_deleted and je.data->>'status'='posted' and je.data->>'currency'=p_currency;
$$;

create or replace function public.erp_change_cloud_fiscal_period_status(p_company_id uuid,p_period_id text,p_new_status text,p_performed_by text,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_period public.erp_fiscal_periods%rowtype; v_old text; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if p_new_status not in ('open','closed') then raise exception 'حالة الفترة غير مدعومة'; end if;
  select * into v_period from public.erp_fiscal_periods where company_id=p_company_id and id=p_period_id and not is_deleted for update;
  if not found then raise exception 'الفترة المالية غير موجودة'; end if;
  v_old:=coalesce(v_period.data->>'status','open');
  if (p_new_status='closed' and v_old<>'open') or (p_new_status='open' and v_old<>'closed') then raise exception 'انتقال حالة الفترة غير مسموح'; end if;
  if p_new_status='open' and coalesce(trim(p_reason),'')='' then raise exception 'سبب إعادة الفتح مطلوب'; end if;
  update public.erp_fiscal_periods set data=data||jsonb_build_object('status',p_new_status,'closedBy',case when p_new_status='closed' then p_performed_by else null end,'closedAt',case when p_new_status='closed' then to_jsonb(v_now) else 'null'::jsonb end,'updatedAt',v_now),updated_at=v_now,updated_by=auth.uid() where company_id=p_company_id and id=p_period_id;
  insert into public.erp_fiscal_period_events(company_id,id,data,created_by,updated_by) values(p_company_id,gen_random_uuid()::text,jsonb_build_object('id',gen_random_uuid()::text,'fiscalPeriodId',p_period_id,'action',case when p_new_status='closed' then 'close' else 'reopen' end,'previousStatus',v_old,'newStatus',p_new_status,'performedBy',p_performed_by,'reason',p_reason,'createdAt',v_now),auth.uid(),auth.uid());
end $$;

grant execute on function public.erp_save_cloud_ledger_account(uuid,jsonb,boolean),public.erp_delete_cloud_ledger_account(uuid,text),public.erp_post_cloud_manual_journal(uuid,jsonb,jsonb),public.erp_delete_cloud_manual_journal(uuid,text),public.erp_cloud_account_statement(uuid,text,timestamptz,timestamptz),public.erp_cloud_trial_balance(uuid,text),public.erp_change_cloud_fiscal_period_status(uuid,text,text,text,text) to authenticated;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['erp_fiscal_years','erp_fiscal_periods','erp_fiscal_period_events'] LOOP
    BEGIN EXECUTE format('alter publication supabase_realtime add table public.%I',t); EXCEPTION WHEN duplicate_object THEN NULL; END;
  END LOOP;
END $$;

commit;
