begin;

create table if not exists public.erp_cost_centers (like public.erp_cars including all);
create table if not exists public.erp_accounting_projects (like public.erp_cars including all);
create table if not exists public.erp_recurring_journal_templates (like public.erp_cars including all);
create table if not exists public.erp_recurring_journal_lines (like public.erp_cars including all);
create table if not exists public.erp_fiscal_closings (like public.erp_cars including all);

create unique index if not exists erp_cost_centers_code_uq on public.erp_cost_centers(company_id,lower(data->>'code')) where not is_deleted;
create unique index if not exists erp_accounting_projects_code_uq on public.erp_accounting_projects(company_id,lower(data->>'code')) where not is_deleted;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['erp_cost_centers','erp_accounting_projects','erp_recurring_journal_templates','erp_recurring_journal_lines','erp_fiscal_closings'] LOOP
    EXECUTE format('alter table public.%I enable row level security',t);
    EXECUTE format('drop policy if exists %I on public.%I',t||'_tenant',t);
    EXECUTE format('create policy %I on public.%I for all to authenticated using (public.is_active_company_member(company_id)) with check (public.is_active_company_member(company_id))',t||'_tenant',t);
    EXECUTE format('grant select on public.%I to authenticated',t);
  END LOOP;
END $$;

create or replace function public.erp_resolve_cloud_open_period(p_company_id uuid,p_entry_date timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_period public.erp_fiscal_periods%rowtype; v_year public.erp_fiscal_years%rowtype;
begin
  if not public.is_active_company_member(p_company_id) then raise exception 'access denied'; end if;
  select * into v_period from public.erp_fiscal_periods where company_id=p_company_id and not is_deleted and p_entry_date between (data->>'startDate')::timestamptz and (data->>'endDate')::timestamptz limit 1;
  if not found then raise exception 'لا توجد فترة مالية معرفة لهذا التاريخ'; end if;
  select * into v_year from public.erp_fiscal_years where company_id=p_company_id and id=v_period.data->>'fiscalYearId' and not is_deleted limit 1;
  if coalesce(v_period.data->>'status','open')<>'open' or coalesce(v_year.data->>'status','open')<>'open' then raise exception 'لا يمكن الترحيل إلى سنة أو فترة مالية مغلقة'; end if;
  return v_period.data||jsonb_build_object('fiscalYearStatus',v_year.data->>'status');
end $$;

create or replace function public.erp_assign_cloud_entry_dimensions(p_company_id uuid,p_entry_id text,p_entry_date timestamptz,p_cost_center_id text,p_project_id text)
returns void language plpgsql security definer set search_path=public as $$
declare v_period jsonb; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  v_period:=public.erp_resolve_cloud_open_period(p_company_id,p_entry_date);
  if p_cost_center_id is not null and not exists(select 1 from public.erp_cost_centers where company_id=p_company_id and id=p_cost_center_id and not is_deleted and coalesce((data->>'isActive')::boolean,true)) then raise exception 'مركز الكلفة غير موجود أو غير فعال'; end if;
  if p_project_id is not null and not exists(select 1 from public.erp_accounting_projects where company_id=p_company_id and id=p_project_id and not is_deleted and coalesce(data->>'status','active')='active') then raise exception 'المشروع المحاسبي غير موجود أو غير فعال'; end if;
  update public.erp_journal_entries set data=data||jsonb_build_object('fiscalYearId',v_period->>'fiscalYearId','fiscalPeriodId',v_period->>'id','costCenterId',p_cost_center_id,'projectId',p_project_id,'updatedAt',v_now),updated_at=v_now,updated_by=auth.uid() where company_id=p_company_id and id=p_entry_id and not is_deleted;
  if not found then raise exception 'القيد غير موجود'; end if;
end $$;

create or replace function public.erp_save_cloud_cost_center(p_company_id uuid,p_cost_center jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_cost_center->>'id'; v_parent text:=nullif(p_cost_center->>'parentId',''); v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(trim(p_cost_center->>'code'),'')='' or coalesce(trim(p_cost_center->>'nameAr'),'')='' then raise exception 'بيانات مركز الكلفة غير مكتملة'; end if;
  if v_parent is not null and not exists(select 1 from public.erp_cost_centers where company_id=p_company_id and id=v_parent and not is_deleted and coalesce((data->>'isActive')::boolean,true)) then raise exception 'مركز الكلفة الأب غير موجود أو غير فعال'; end if;
  insert into public.erp_cost_centers(company_id,id,data,created_by,updated_by) values(p_company_id,v_id,p_cost_center||jsonb_build_object('createdAt',coalesce(p_cost_center->'createdAt',to_jsonb(v_now)),'updatedAt',v_now),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=v_now,updated_by=auth.uid();
end $$;

create or replace function public.erp_save_cloud_accounting_project(p_company_id uuid,p_project jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_project->>'id'; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(trim(p_project->>'code'),'')='' or coalesce(trim(p_project->>'nameAr'),'')='' then raise exception 'بيانات المشروع غير مكتملة'; end if;
  if coalesce((p_project->>'budgetAmount')::numeric,0)<0 then raise exception 'ميزانية المشروع غير صحيحة'; end if;
  insert into public.erp_accounting_projects(company_id,id,data,created_by,updated_by) values(p_company_id,v_id,p_project||jsonb_build_object('createdAt',coalesce(p_project->'createdAt',to_jsonb(v_now)),'updatedAt',v_now),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=v_now,updated_by=auth.uid();
end $$;

create or replace function public.erp_post_cloud_recurring_template(p_company_id uuid,p_template_id text,p_posting_date timestamptz,p_user_id text)
returns text language plpgsql security definer set search_path=public as $$
declare v_template public.erp_recurring_journal_templates%rowtype; v_line jsonb; v_lines jsonb:='[]'::jsonb; v_entry jsonb; v_entry_id text:=gen_random_uuid()::text; v_debit numeric:=0; v_credit numeric:=0; v_frequency text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_template from public.erp_recurring_journal_templates where company_id=p_company_id and id=p_template_id and not is_deleted and coalesce((data->>'isActive')::boolean,true) for update;
  if not found then raise exception 'قالب القيد الدوري غير موجود أو غير فعال'; end if;
  for v_line in select data from public.erp_recurring_journal_lines where company_id=p_company_id and not is_deleted and data->>'templateId'=p_template_id order by (data->>'lineOrder')::int loop
    v_debit:=v_debit+coalesce((v_line->>'debit')::numeric,0); v_credit:=v_credit+coalesce((v_line->>'credit')::numeric,0);
    v_lines:=v_lines||jsonb_build_array(v_line||jsonb_build_object('id',gen_random_uuid()::text,'entryId',v_entry_id));
  end loop;
  if jsonb_array_length(v_lines)<2 or abs(v_debit-v_credit)>0.01 then raise exception 'قالب القيد الدوري غير مكتمل أو غير متوازن'; end if;
  v_entry:=jsonb_build_object('id',v_entry_id,'entryNumber','REC-'||extract(epoch from clock_timestamp())::bigint,'entryDate',p_posting_date,'description',coalesce(v_template.data->>'description',v_template.data->>'nameAr'),'currency',v_template.data->>'currency','referenceType','recurring_journal','referenceId',p_template_id,'sourceTemplateId',p_template_id,'createdBy',p_user_id);
  perform public.erp_post_cloud_manual_journal(p_company_id,v_entry,v_lines);
  v_frequency:=coalesce(v_template.data->>'frequency','monthly');
  update public.erp_recurring_journal_templates set data=data||jsonb_build_object('nextRunDate',case v_frequency when 'weekly' then p_posting_date+interval '7 days' when 'quarterly' then p_posting_date+interval '3 months' when 'yearly' then p_posting_date+interval '1 year' else p_posting_date+interval '1 month' end,'updatedAt',now()),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=p_template_id;
  return v_entry_id;
end $$;

create or replace function public.erp_close_cloud_fiscal_year(p_company_id uuid,p_fiscal_year_id text,p_retained_earnings_account_id text,p_user_id text)
returns void language plpgsql security definer set search_path=public as $$
declare v_year public.erp_fiscal_years%rowtype; v_net numeric:=0; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_year from public.erp_fiscal_years where company_id=p_company_id and id=p_fiscal_year_id and not is_deleted for update;
  if not found then raise exception 'السنة المالية غير موجودة'; end if;
  if exists(select 1 from public.erp_fiscal_periods where company_id=p_company_id and not is_deleted and data->>'fiscalYearId'=p_fiscal_year_id and data->>'status'='open') then raise exception 'يجب إغلاق جميع الفترات قبل إقفال السنة'; end if;
  if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=p_retained_earnings_account_id and is_active) then raise exception 'حساب الأرباح المحتجزة غير موجود أو غير فعال'; end if;
  select coalesce(sum(case when a.account_type='revenue' then (jl.data->>'credit')::numeric-(jl.data->>'debit')::numeric else (jl.data->>'debit')::numeric-(jl.data->>'credit')::numeric end),0) into v_net
  from public.erp_journal_lines jl join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId' join public.erp_accounts a on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
  where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted and je.data->>'status'='posted' and je.data->>'fiscalYearId'=p_fiscal_year_id and a.account_type in ('revenue','expense');
  insert into public.erp_fiscal_closings(company_id,id,data,created_by,updated_by) values(p_company_id,gen_random_uuid()::text,jsonb_build_object('fiscalYearId',p_fiscal_year_id,'retainedEarningsAccountId',p_retained_earnings_account_id,'status','approved','summaryJson',jsonb_build_object('netIncome',v_net),'approvedBy',p_user_id,'approvedAt',v_now,'createdBy',p_user_id,'createdAt',v_now),auth.uid(),auth.uid());
  update public.erp_fiscal_years set data=data||jsonb_build_object('status','closed','closedBy',p_user_id,'closedAt',v_now,'updatedAt',v_now),updated_at=v_now,updated_by=auth.uid() where company_id=p_company_id and id=p_fiscal_year_id;
end $$;

create or replace function public.erp_cloud_professional_accounting_report(p_company_id uuid,p_report_type text,p_currency text default 'ALL',p_branch_id text default null,p_cost_center_id text default null,p_from_date timestamptz default null,p_to_date timestamptz default null)
returns setof jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_active_company_member(p_company_id) then raise exception 'access denied'; end if;
  if p_report_type='cashFlow' then
    return query select jsonb_build_object('currency',data->>'currency','cashIn',sum(case when data->>'type' in ('income','receipt','in','customer_receipt','transfer_in') then coalesce((data->>'amount')::numeric,0) else 0 end),'cashOut',sum(case when data->>'type' in ('expense','payment','out','supplier_payment','transfer_out') then coalesce((data->>'amount')::numeric,0) else 0 end),'netCashFlow',sum(case when data->>'type' in ('income','receipt','in','customer_receipt','transfer_in') then coalesce((data->>'amount')::numeric,0) else -coalesce((data->>'amount')::numeric,0) end)) from public.erp_cash_transactions where company_id=p_company_id and not is_deleted and (p_currency='ALL' or data->>'currency'=p_currency) and (p_from_date is null or (data->>'transactionDate')::timestamptz>=p_from_date) and (p_to_date is null or (data->>'transactionDate')::timestamptz<=p_to_date) group by data->>'currency';
  elsif p_report_type='generalLedger' then
    return query select jsonb_build_object('entryDate',je.data->>'entryDate','entryNumber',je.data->>'entryNumber','accountCode',jl.data->>'accountCode','accountName',jl.data->>'accountName','currency',je.data->>'currency','debit',coalesce((jl.data->>'debit')::numeric,0),'credit',coalesce((jl.data->>'credit')::numeric,0),'description',coalesce(jl.data->>'description',je.data->>'description')) from public.erp_journal_lines jl join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId' where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted and je.data->>'status'='posted' and (p_currency='ALL' or je.data->>'currency'=p_currency) and (p_branch_id is null or je.data->>'branchId'=p_branch_id) and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId',je.data->>'costCenterId')=p_cost_center_id) and (p_from_date is null or (je.data->>'entryDate')::timestamptz>=p_from_date) and (p_to_date is null or (je.data->>'entryDate')::timestamptz<=p_to_date) order by jl.data->>'accountCode',(je.data->>'entryDate')::timestamptz,je.created_at,jl.created_at;
  else
    return query select jsonb_build_object('code',a.code,'name',a.name,'type',a.account_type,'currency',a.currency,'openingBalance',a.opening_balance,'debit',coalesce(sum((jl.data->>'debit')::numeric),0),'credit',coalesce(sum((jl.data->>'credit')::numeric),0),'balance',case when a.account_type in ('liability','equity','revenue') then a.opening_balance+coalesce(sum((jl.data->>'credit')::numeric-(jl.data->>'debit')::numeric),0) else a.opening_balance+coalesce(sum((jl.data->>'debit')::numeric-(jl.data->>'credit')::numeric),0) end) from public.erp_accounts a left join public.erp_journal_lines jl on jl.company_id=a.organization_id and jl.data->>'accountId'=a.account_id and not jl.is_deleted left join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId' and not je.is_deleted and je.data->>'status'='posted' where a.organization_id=p_company_id and a.is_active and (p_currency='ALL' or coalesce(je.data->>'currency',a.currency)=p_currency) and (p_branch_id is null or je.data->>'branchId'=p_branch_id) and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId',je.data->>'costCenterId')=p_cost_center_id) and (p_from_date is null or (je.data->>'entryDate')::timestamptz>=p_from_date) and (p_to_date is null or (je.data->>'entryDate')::timestamptz<=p_to_date) group by a.account_id,a.code,a.name,a.account_type,a.currency,a.opening_balance order by a.code;
  end if;
end $$;

grant execute on function public.erp_resolve_cloud_open_period(uuid,timestamptz),public.erp_assign_cloud_entry_dimensions(uuid,text,timestamptz,text,text),public.erp_save_cloud_cost_center(uuid,jsonb),public.erp_save_cloud_accounting_project(uuid,jsonb),public.erp_post_cloud_recurring_template(uuid,text,timestamptz,text),public.erp_close_cloud_fiscal_year(uuid,text,text,text),public.erp_cloud_professional_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) to authenticated;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['erp_cost_centers','erp_accounting_projects','erp_recurring_journal_templates','erp_recurring_journal_lines','erp_fiscal_closings'] LOOP
    BEGIN EXECUTE format('alter publication supabase_realtime add table public.%I',t); EXCEPTION WHEN duplicate_object THEN NULL; END;
  END LOOP;
END $$;

commit;
