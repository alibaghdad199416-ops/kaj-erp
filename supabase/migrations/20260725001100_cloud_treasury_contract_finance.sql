-- Phase 17: Supabase-only advanced treasury and contract finance.

create table if not exists public.erp_bank_accounts (
  company_id uuid not null,
  id uuid not null,
  data jsonb not null default '{}'::jsonb,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (company_id, id)
);
create table if not exists public.erp_treasury_cheques (like public.erp_bank_accounts including all);
create table if not exists public.erp_bank_reconciliations (like public.erp_bank_accounts including all);
create table if not exists public.erp_contract_warranties (like public.erp_bank_accounts including all);
create table if not exists public.erp_contract_warranty_claims (like public.erp_bank_accounts including all);
create table if not exists public.erp_contract_installment_plans (like public.erp_bank_accounts including all);
create table if not exists public.erp_contract_installment_schedule (like public.erp_bank_accounts including all);
create table if not exists public.erp_contract_installment_payments (like public.erp_bank_accounts including all);
create table if not exists public.erp_contract_reschedule_history (like public.erp_bank_accounts including all);

create index if not exists erp_bank_accounts_cash_idx on public.erp_bank_accounts(company_id, ((data->>'cashAccountId')));
create unique index if not exists erp_treasury_cheques_number_uq on public.erp_treasury_cheques(company_id, ((data->>'chequeNumber'))) where not is_deleted;
create index if not exists erp_treasury_cheques_due_idx on public.erp_treasury_cheques(company_id, ((data->>'dueDate')));
create unique index if not exists erp_contract_warranty_number_uq on public.erp_contract_warranties(company_id, ((data->>'warrantyNumber'))) where not is_deleted;
create index if not exists erp_contract_plan_contract_idx on public.erp_contract_installment_plans(company_id, ((data->>'contractId')));
create index if not exists erp_contract_schedule_plan_idx on public.erp_contract_installment_schedule(company_id, ((data->>'planId')), ((data->>'installmentNumber')));

alter table public.erp_bank_accounts enable row level security;
alter table public.erp_treasury_cheques enable row level security;
alter table public.erp_bank_reconciliations enable row level security;
alter table public.erp_contract_warranties enable row level security;
alter table public.erp_contract_warranty_claims enable row level security;
alter table public.erp_contract_installment_plans enable row level security;
alter table public.erp_contract_installment_schedule enable row level security;
alter table public.erp_contract_installment_payments enable row level security;
alter table public.erp_contract_reschedule_history enable row level security;

-- Reuse the project's authoritative membership check.
do $$
declare t text;
begin
  foreach t in array array[
    'erp_bank_accounts','erp_treasury_cheques','erp_bank_reconciliations',
    'erp_contract_warranties','erp_contract_warranty_claims',
    'erp_contract_installment_plans','erp_contract_installment_schedule',
    'erp_contract_installment_payments','erp_contract_reschedule_history'
  ] loop
    execute format('drop policy if exists tenant_access on public.%I', t);
    execute format(
      'create policy tenant_access on public.%I for all using (public.erp_user_belongs_to_company(company_id)) with check (public.erp_user_belongs_to_company(company_id))', t
    );
  end loop;
end $$;

create or replace function public.erp_list_cloud_bank_accounts(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
  select b.data || jsonb_build_object(
    'id', b.id,
    'cashAccountName', coalesce(c.data->>'name',''),
    'currency', coalesce(b.data->>'currency', c.data->>'currency')
  )
  from erp_bank_accounts b
  left join erp_cash_accounts c on c.company_id=b.company_id
    and c.id=btrim(b.data->>'cashAccountId') and not c.is_deleted
  where b.company_id=p_company_id and not b.is_deleted
    and erp_user_belongs_to_company(p_company_id)
  order by coalesce((b.data->>'isActive')::boolean,true) desc, b.data->>'bankName';
$$;

create or replace function public.erp_save_cloud_bank_account(p_company_id uuid, p_bank_account jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid := (p_bank_account->>'id')::uuid; v_cash jsonb;
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  select data into v_cash from erp_cash_accounts where company_id=p_company_id
    and id=btrim(p_bank_account->>'cashAccountId') and not is_deleted for update;
  if v_cash is null or coalesce(v_cash->>'type','') <> 'bank' or not coalesce((v_cash->>'isActive')::boolean,true) then
    raise exception 'active bank cash account is required';
  end if;
  insert into erp_bank_accounts(company_id,id,data,is_deleted,deleted_at,updated_at)
  values(p_company_id,v_id,p_bank_account || jsonb_build_object('currency',v_cash->>'currency','isActive',true),false,null,now())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();
  return v_id;
end $$;

create or replace function public.erp_issue_cloud_cheque(p_company_id uuid, p_cheque jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid := (p_cheque->>'id')::uuid; v_cash jsonb;
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  if (p_cheque->>'direction') not in ('incoming','outgoing') then raise exception 'invalid cheque direction'; end if;
  if (p_cheque->>'amount')::numeric <= 0 or (p_cheque->>'exchangeRate')::numeric <= 0 then raise exception 'invalid cheque amount'; end if;
  if (p_cheque->>'dueDate')::timestamptz < (p_cheque->>'issueDate')::timestamptz then raise exception 'invalid due date'; end if;
  select data into v_cash from erp_cash_accounts where company_id=p_company_id
    and id=btrim(p_cheque->>'cashAccountId') and not is_deleted for update;
  if v_cash is null or not coalesce((v_cash->>'isActive')::boolean,true) then raise exception 'cash account not found'; end if;
  if upper(v_cash->>'currency') <> upper(p_cheque->>'currency') then raise exception 'currency mismatch'; end if;
  insert into erp_treasury_cheques(company_id,id,data)
  values(p_company_id,v_id,p_cheque || jsonb_build_object('status','issued','createdAt',now()))
  on conflict(company_id,id) do nothing;
  return v_id;
end $$;

create or replace function public.erp_clear_cloud_cheque(p_company_id uuid, p_cheque_id uuid, p_user_id text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_cheque jsonb; v_tx jsonb; v_tx_id uuid := gen_random_uuid();
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  select data into v_cheque from erp_treasury_cheques where company_id=p_company_id and id=p_cheque_id and not is_deleted for update;
  if v_cheque is null or v_cheque->>'status' <> 'issued' then raise exception 'cheque is missing or already processed'; end if;
  v_tx := jsonb_build_object(
    'id',v_tx_id,'voucherNumber','CHQ-'||extract(epoch from clock_timestamp())::bigint,
    'type',case when v_cheque->>'direction'='incoming' then 'receipt' else 'payment' end,
    'category',case when v_cheque->>'direction'='incoming' then 'customer_receipt' else 'supplier_payment' end,
    'cashAccountId',v_cheque->>'cashAccountId','amount',(v_cheque->>'amount')::numeric,
    'currency',v_cheque->>'currency','exchangeRate',(v_cheque->>'exchangeRate')::numeric,
    'transactionDate',now(),'referenceType','treasury_cheque','referenceId',p_cheque_id,
    'partyType',coalesce(v_cheque->>'partnerType','other'),'partyId',v_cheque->>'partnerId',
    'partyName',v_cheque->>'partnerName','paymentMethod','cheque','notes',v_cheque->>'notes'
  );
  perform erp_post_cloud_cash_transaction(p_company_id, v_tx);
  update erp_treasury_cheques set data=data || jsonb_build_object(
    'status','cleared','cashTransactionId',v_tx_id,'clearedAt',now(),'clearedBy',p_user_id
  ),updated_at=now() where company_id=p_company_id and id=p_cheque_id;
end $$;

create or replace function public.erp_create_cloud_bank_reconciliation(p_company_id uuid, p_reconciliation jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid := (p_reconciliation->>'id')::uuid; v_bank jsonb; v_balance numeric; v_diff numeric;
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  select data into v_bank from erp_bank_accounts where company_id=p_company_id and id=(p_reconciliation->>'bankAccountId')::uuid and not is_deleted for update;
  if v_bank is null then raise exception 'bank account not found'; end if;
  v_balance := erp_cloud_cash_account_balance(p_company_id,btrim(v_bank->>'cashAccountId'));
  v_diff := (p_reconciliation->>'statementClosingBalance')::numeric-v_balance;
  insert into erp_bank_reconciliations(company_id,id,data) values(p_company_id,v_id,p_reconciliation || jsonb_build_object(
    'reconciliationNumber','REC-'||extract(epoch from clock_timestamp())::bigint,
    'ledgerClosingBalance',v_balance,'difference',v_diff,
    'status',case when abs(v_diff)<0.000001 then 'balanced' else 'draft' end,'createdAt',now()
  ));
  return v_id;
end $$;

create or replace function public.erp_post_cloud_partner_voucher(p_company_id uuid, p_voucher jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid := gen_random_uuid();
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  if (p_voucher->>'type') not in ('receipt','payment') or (p_voucher->>'amount')::numeric<=0 then raise exception 'invalid voucher'; end if;
  perform erp_post_cloud_cash_transaction(p_company_id, p_voucher || jsonb_build_object(
    'id',v_id,'voucherNumber','VCH-'||extract(epoch from clock_timestamp())::bigint,
    'category',case when p_voucher->>'type'='receipt' then 'customer_receipt' else 'supplier_payment' end,
    'transactionDate',now(),'partyType',case when p_voucher->>'type'='receipt' then 'customer' else 'supplier' end,
    'referenceType',case when p_voucher->>'type'='receipt' then 'customer_receipt' else 'supplier_payment' end,
    'referenceId',v_id
  ));
  return v_id;
end $$;

create or replace function public.erp_cloud_cash_account_balance(p_company_id uuid, p_account_id text)
returns numeric language sql security definer set search_path=public as $$
  select coalesce((a.data->>'openingBalance')::numeric,0)+coalesce(sum(case when t.data->>'type'='receipt' then (t.data->>'amount')::numeric else -(t.data->>'amount')::numeric end),0)
  from erp_cash_accounts a left join erp_cash_transactions t on t.company_id=a.company_id
    and t.data->>'cashAccountId'=a.id and not t.is_deleted
  where a.company_id=p_company_id and a.id=p_account_id and not a.is_deleted
    and erp_user_belongs_to_company(p_company_id)
  group by a.data;
$$;

create or replace function public.erp_create_cloud_contract_warranty(p_company_id uuid,p_warranty jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid := (p_warranty->>'id')::uuid;
begin
 if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
 if (p_warranty->>'endDate')::timestamptz < (p_warranty->>'startDate')::timestamptz then raise exception 'invalid warranty period'; end if;
 insert into erp_contract_warranties(company_id,id,data) values(p_company_id,v_id,p_warranty||jsonb_build_object('status','active','createdAt',now())); return v_id;
end $$;

create or replace function public.erp_submit_cloud_warranty_claim(p_company_id uuid,p_claim jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid := (p_claim->>'id')::uuid; v_w jsonb; v_count int; v_total numeric;
begin
 if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
 select data into v_w from erp_contract_warranties where company_id=p_company_id and id=(p_claim->>'warrantyId')::uuid and not is_deleted for update;
 if v_w is null or v_w->>'status'<>'active' or now()>(v_w->>'endDate')::timestamptz then raise exception 'active warranty not found'; end if;
 select count(*),coalesce(sum((data->>'requestedAmount')::numeric),0) into v_count,v_total from erp_contract_warranty_claims where company_id=p_company_id and data->>'warrantyId'=p_claim->>'warrantyId' and not is_deleted;
 if v_w->>'maxClaims' is not null and v_count >= (v_w->>'maxClaims')::int then raise exception 'maximum warranty claims reached'; end if;
 if v_w->>'maxCoverageAmount' is not null and v_total+(p_claim->>'requestedAmount')::numeric > (v_w->>'maxCoverageAmount')::numeric then raise exception 'maximum warranty coverage exceeded'; end if;
 insert into erp_contract_warranty_claims(company_id,id,data) values(p_company_id,v_id,p_claim||jsonb_build_object('claimDate',now(),'status','submitted','createdAt',now())); return v_id;
end $$;

create or replace function public.erp_create_cloud_contract_installment_plan(p_company_id uuid,p_plan jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid := (p_plan->>'id')::uuid; v_total numeric; v_base numeric; v_due date; v_amount numeric; i int;
begin
 if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
 if (p_plan->>'principalAmount')::numeric<=0 or (p_plan->>'installmentCount')::int<=0 then raise exception 'invalid installment plan'; end if;
 v_total:=(p_plan->>'principalAmount')::numeric+coalesce((p_plan->>'interestAmount')::numeric,0); v_base:=v_total/(p_plan->>'installmentCount')::int; v_due:=(p_plan->>'firstDueDate')::date;
 insert into erp_contract_installment_plans(company_id,id,data) values(p_company_id,v_id,p_plan||jsonb_build_object('paidAmount',0,'outstandingAmount',v_total,'status','active','version',1,'createdAt',now()));
 for i in 1..(p_plan->>'installmentCount')::int loop
   v_amount:=case when i=(p_plan->>'installmentCount')::int then v_total-v_base*(i-1) else v_base end;
   insert into erp_contract_installment_schedule(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('planId',v_id,'installmentNumber',i,'dueDate',v_due,'principalAmount',v_amount*((p_plan->>'principalAmount')::numeric/v_total),'interestAmount',v_amount*(coalesce((p_plan->>'interestAmount')::numeric,0)/v_total),'paidAmount',0,'remainingAmount',v_amount,'status','pending','createdAt',now()));
   v_due:=case p_plan->>'frequency' when 'weekly' then v_due+7 when 'quarterly' then (v_due+interval '3 months')::date when 'yearly' then (v_due+interval '1 year')::date else (v_due+interval '1 month')::date end;
 end loop; return v_id;
end $$;

create or replace function public.erp_record_cloud_contract_payment(p_company_id uuid,p_payment jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_plan_id uuid := (p_payment->>'planId')::uuid; v_plan jsonb; v_left numeric := (p_payment->>'amount')::numeric; r record; v_apply numeric; v_tx uuid := gen_random_uuid();
begin
 if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
 select data into v_plan from erp_contract_installment_plans where company_id=p_company_id and id=v_plan_id and not is_deleted for update;
 if v_plan is null or v_left<=0 or v_left>(v_plan->>'outstandingAmount')::numeric then raise exception 'invalid payment'; end if;
 for r in select id,data from erp_contract_installment_schedule where company_id=p_company_id and data->>'planId'=v_plan_id::text and not is_deleted and data->>'status'<>'paid' order by (data->>'installmentNumber')::int for update loop
   exit when v_left<=0; v_apply:=least(v_left,(r.data->>'remainingAmount')::numeric);
   update erp_contract_installment_schedule set data=data||jsonb_build_object('paidAmount',coalesce((data->>'paidAmount')::numeric,0)+v_apply,'remainingAmount',(data->>'remainingAmount')::numeric-v_apply,'status',case when (data->>'remainingAmount')::numeric-v_apply<=0.000001 then 'paid' else 'partial' end,'lastPaymentAt',now()),updated_at=now() where company_id=p_company_id and id=r.id;
   v_left:=v_left-v_apply;
 end loop;
 perform erp_post_cloud_cash_transaction(p_company_id,p_payment||jsonb_build_object('id',v_tx,'voucherNumber','INST-'||extract(epoch from clock_timestamp())::bigint,'type','receipt','category','installment_payment','transactionDate',now(),'referenceType','contract_installment_plan','referenceId',v_plan_id,'cashAccountId',p_payment->>'cashAccountId'));
 insert into erp_contract_installment_payments(company_id,id,data) values(p_company_id,(p_payment->>'id')::uuid,p_payment||jsonb_build_object('cashTransactionId',v_tx,'paymentDate',now(),'createdAt',now()));
 update erp_contract_installment_plans set data=data||jsonb_build_object('paidAmount',(data->>'paidAmount')::numeric+(p_payment->>'amount')::numeric,'outstandingAmount',(data->>'outstandingAmount')::numeric-(p_payment->>'amount')::numeric,'status',case when (data->>'outstandingAmount')::numeric-(p_payment->>'amount')::numeric<=0.000001 then 'paid' else 'active' end),updated_at=now() where company_id=p_company_id and id=v_plan_id;
end $$;

create or replace function public.erp_reschedule_cloud_contract_plan(p_company_id uuid,p_plan_id uuid,p_schedule jsonb,p_reason text,p_performed_by text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_plan jsonb; v_previous jsonb; v_version int; r jsonb; i int:=0; v_amount numeric;
begin
 if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
 if jsonb_array_length(p_schedule)=0 or btrim(p_reason)='' then raise exception 'schedule and reason required'; end if;
 select data into v_plan from erp_contract_installment_plans where company_id=p_company_id and id=p_plan_id and not is_deleted for update;
 if v_plan is null then raise exception 'plan not found'; end if;
 select coalesce(jsonb_agg(data order by (data->>'installmentNumber')::int),'[]'::jsonb) into v_previous from erp_contract_installment_schedule where company_id=p_company_id and data->>'planId'=p_plan_id::text and not is_deleted;
 update erp_contract_installment_schedule set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and data->>'planId'=p_plan_id::text and data->>'status'='pending' and not is_deleted;
 for r in select value from jsonb_array_elements(p_schedule) loop i:=i+1; v_amount:=(r->>'amount')::numeric; insert into erp_contract_installment_schedule(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('planId',p_plan_id,'installmentNumber',i,'dueDate',r->>'dueDate','principalAmount',v_amount,'paidAmount',0,'remainingAmount',v_amount,'status','pending','createdAt',now())); end loop;
 v_version:=coalesce((v_plan->>'version')::int,1);
 insert into erp_contract_reschedule_history(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('planId',p_plan_id,'previousVersion',v_version,'newVersion',v_version+1,'reason',p_reason,'previousSchedule',v_previous,'newSchedule',p_schedule,'performedBy',p_performed_by,'performedAt',now()));
 update erp_contract_installment_plans set data=data||jsonb_build_object('version',v_version+1,'installmentCount',jsonb_array_length(p_schedule)),updated_at=now() where company_id=p_company_id and id=p_plan_id;
end $$;

-- Include the new tables in Realtime when the publication exists.
do $$ declare t text; begin
  foreach t in array array['erp_bank_accounts','erp_treasury_cheques','erp_bank_reconciliations','erp_contract_warranties','erp_contract_warranty_claims','erp_contract_installment_plans','erp_contract_installment_schedule','erp_contract_installment_payments','erp_contract_reschedule_history'] loop
    begin execute format('alter publication supabase_realtime add table public.%I',t); exception when duplicate_object then null; end;
  end loop;
end $$;
