begin;

create table if not exists public.erp_cash_accounts (like public.erp_cars including all);
create table if not exists public.erp_cash_transactions (like public.erp_cars including all);
create table if not exists public.erp_cash_transfers (like public.erp_cars including all);
create table if not exists public.erp_journal_entries (like public.erp_cars including all);
create table if not exists public.erp_journal_lines (like public.erp_cars including all);

create unique index if not exists erp_cash_accounts_name_uq
  on public.erp_cash_accounts(company_id, lower(data->>'name')) where not is_deleted;
create unique index if not exists erp_cash_transactions_voucher_uq
  on public.erp_cash_transactions(company_id, lower(data->>'voucherNumber')) where not is_deleted;
create index if not exists erp_cash_transactions_account_idx
  on public.erp_cash_transactions(company_id, (data->>'cashAccountId'), (data->>'transactionDate')) where not is_deleted;
create index if not exists erp_journal_lines_entry_idx
  on public.erp_journal_lines(company_id, (data->>'entryId')) where not is_deleted;
create index if not exists erp_installments_due_idx
  on public.erp_installments(company_id, (data->>'dueDate')) where not is_deleted;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['erp_cash_accounts','erp_cash_transactions','erp_cash_transfers','erp_journal_entries','erp_journal_lines'] LOOP
    EXECUTE format('alter table public.%I enable row level security', t);
    EXECUTE format('drop policy if exists %I_select on public.%I', t, t);
    EXECUTE format('drop policy if exists %I_insert on public.%I', t, t);
    EXECUTE format('drop policy if exists %I_update on public.%I', t, t);
    EXECUTE format('create policy %I_select on public.%I for select to authenticated using (public.is_active_company_member(company_id))', t, t);
    EXECUTE format('create policy %I_insert on public.%I for insert to authenticated with check (public.can_manage_master_data(company_id))', t, t);
    EXECUTE format('create policy %I_update on public.%I for update to authenticated using (public.can_manage_master_data(company_id)) with check (public.can_manage_master_data(company_id))', t, t);
    EXECUTE format('drop trigger if exists %I_before_write on public.%I', t, t);
    EXECUTE format('create trigger %I_before_write before insert or update on public.%I for each row execute function public.erp_master_before_write()', t, t);
  END LOOP;
END $$;

grant select,insert,update on public.erp_cash_accounts,public.erp_cash_transactions,
  public.erp_cash_transfers,public.erp_journal_entries,public.erp_journal_lines to authenticated;

create or replace function public.erp_save_cloud_cash_account(p_company_id uuid,p_account jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_account->>'id'; v_ledger text:=p_account->>'account_id';
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(p_account->>'name','')='' or coalesce(v_ledger,'')='' then
    raise exception 'بيانات الصندوق غير مكتملة';
  end if;
  if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_ledger and is_active) then
    raise exception 'الحساب المحاسبي المختار غير موجود أو غير فعال';
  end if;
  insert into public.erp_cash_accounts(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'id',v_id,'name',p_account->>'name','type',coalesce(p_account->>'type','cash'),
    'currency',coalesce(p_account->>'currency','USD'),
    'openingBalance',coalesce((p_account->>'opening_balance')::numeric,0),
    'isActive',coalesce((p_account->>'is_active')::boolean,true),
    'accountId',v_ledger,'createdAt',coalesce(p_account->'created_at',to_jsonb(now())),
    'updatedAt',to_jsonb(now())),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,
    updated_at=now(),updated_by=auth.uid();
end $$;

create or replace function public.erp_delete_cloud_cash_account(p_company_id uuid,p_cash_account_id text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if exists(select 1 from public.erp_cash_transactions where company_id=p_company_id and not is_deleted and data->>'cashAccountId'=p_cash_account_id) then
    raise exception 'لا يمكن حذف صندوق مرتبط بحركات مالية. يمكن تعطيله بدلاً من ذلك';
  end if;
  update public.erp_cash_accounts set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=p_cash_account_id and not is_deleted;
end $$;

create or replace function public.erp_post_cloud_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=p_transaction->>'id'; v_cash_id text:=p_transaction->>'cashAccountId';
  v_counter_id text:=p_transaction->>'counterAccountId'; v_type text:=p_transaction->>'type';
  v_amount numeric:=coalesce((p_transaction->>'amount')::numeric,0);
  v_cash public.erp_cash_accounts%rowtype; v_journal_id text:=gen_random_uuid()::text;
  v_old_journal text; v_now timestamptz:=now(); v_cash_debit numeric:=0; v_cash_credit numeric:=0;
  v_cash_account record; v_counter record; v_payload jsonb;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(p_transaction->>'voucherNumber','')='' or v_amount<=0 or v_type not in ('receipt','payment') then
    raise exception 'بيانات حركة الصندوق غير صحيحة';
  end if;
  select * into v_cash from public.erp_cash_accounts where company_id=p_company_id and id=v_cash_id and not is_deleted for update;
  if not found or not coalesce((v_cash.data->>'isActive')::boolean,true) then raise exception 'الصندوق غير موجود أو غير فعال'; end if;
  select account_id,code,name,currency into v_cash_account from public.erp_accounts
    where organization_id=p_company_id and account_id=v_cash.data->>'accountId' and is_active;
  select account_id,code,name,currency into v_counter from public.erp_accounts
    where organization_id=p_company_id and account_id=v_counter_id and is_active;
  if v_cash_account.account_id is null or v_counter.account_id is null then raise exception 'الحساب المحاسبي غير موجود أو غير فعال'; end if;
  if v_cash_account.account_id=v_counter.account_id then raise exception 'الحساب المقابل يجب أن يختلف عن حساب الصندوق'; end if;
  select data->>'journalEntryId' into v_old_journal from public.erp_cash_transactions
    where company_id=p_company_id and id=v_id and not is_deleted for update;
  if p_replace and v_old_journal is null then raise exception 'لم يتم العثور على حركة الصندوق المطلوبة'; end if;
  if not p_replace and v_old_journal is not null then raise exception 'رقم الحركة مستخدم مسبقاً'; end if;
  if v_old_journal is not null then
    update public.erp_journal_lines set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
      where company_id=p_company_id and not is_deleted and data->>'entryId'=v_old_journal;
    update public.erp_journal_entries set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
      where company_id=p_company_id and id=v_old_journal and not is_deleted;
  end if;
  v_payload:=p_transaction||jsonb_build_object('journalEntryId',v_journal_id,'updatedAt',v_now);
  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,v_payload,auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=v_now,updated_by=auth.uid();
  if v_type='receipt' then v_cash_debit:=v_amount; else v_cash_credit:=v_amount; end if;
  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_journal_id,jsonb_build_object(
    'id',v_journal_id,'entryNumber','CASH-'||(p_transaction->>'voucherNumber'),
    'entryDate',p_transaction->>'transactionDate','description',case when v_type='receipt' then 'قبض نقدي' else 'صرف نقدي' end||' - '||coalesce(p_transaction->>'category',''),
    'currency',p_transaction->>'currency','referenceType','cash_transaction','referenceId',v_id,
    'totalDebit',v_amount,'totalCredit',v_amount,'status','posted','createdAt',v_now),auth.uid(),auth.uid());
  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_cash_account.account_id,'accountCode',v_cash_account.code,'accountName',v_cash_account.name,'debit',v_cash_debit,'credit',v_cash_credit,'description',coalesce(p_transaction->>'notes','')),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_counter.account_id,'accountCode',v_counter.code,'accountName',v_counter.name,'debit',v_cash_credit,'credit',v_cash_debit,'description',coalesce(p_transaction->>'notes','')),auth.uid(),auth.uid());
end $$;

create or replace function public.erp_delete_cloud_cash_transaction(p_company_id uuid,p_transaction_id text)
returns void language plpgsql security definer set search_path=public as $$
declare v_journal text; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select data->>'journalEntryId' into v_journal from public.erp_cash_transactions
    where company_id=p_company_id and id=p_transaction_id and not is_deleted for update;
  if v_journal is null then raise exception 'لم يتم العثور على حركة الصندوق المطلوبة'; end if;
  update public.erp_cash_transactions set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=p_transaction_id;
  update public.erp_journal_entries set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_journal;
  update public.erp_journal_lines set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and data->>'entryId'=v_journal;
end $$;

create or replace function public.erp_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric,
  p_transfer_date timestamptz,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare v_from public.erp_cash_accounts%rowtype; v_to public.erp_cash_accounts%rowtype; v_transfer text:=gen_random_uuid()::text; v_number text:='TR-'||floor(extract(epoch from clock_timestamp())*1000000)::bigint; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if p_from_cash_account_id=p_to_cash_account_id or p_source_amount<=0 or p_target_amount<=0 or p_exchange_rate<=0 then raise exception 'بيانات التحويل غير صحيحة'; end if;
  select * into v_from from public.erp_cash_accounts where company_id=p_company_id and id=p_from_cash_account_id and not is_deleted for update;
  select * into v_to from public.erp_cash_accounts where company_id=p_company_id and id=p_to_cash_account_id and not is_deleted for update;
  if not found or v_from.id is null or v_to.id is null then raise exception 'أحد الصندوقين غير موجود'; end if;
  insert into public.erp_cash_transfers(company_id,id,data,created_by,updated_by) values(p_company_id,v_transfer,jsonb_build_object('id',v_transfer,'transferNumber',v_number,'fromAccountId',p_from_cash_account_id,'toAccountId',p_to_cash_account_id,'sourceAmount',p_source_amount,'sourceCurrency',v_from.data->>'currency','targetAmount',p_target_amount,'targetCurrency',v_to.data->>'currency','exchangeRate',p_exchange_rate,'transferDate',p_transfer_date,'notes',p_notes,'createdAt',v_now),auth.uid(),auth.uid());
  perform public.erp_post_cloud_cash_transaction(p_company_id,jsonb_build_object('id',gen_random_uuid()::text,'voucherNumber',v_number||'-OUT','type','payment','category','تحويل بين الصناديق','amount',p_source_amount,'currency',v_from.data->>'currency','transactionDate',p_transfer_date,'partyType','cash_account','partyId',p_to_cash_account_id,'partyName',v_to.data->>'name','paymentMethod','bank_transfer','referenceType','cash_transfer','referenceId',v_transfer,'notes',p_notes,'createdAt',v_now,'cashAccountId',p_from_cash_account_id,'counterAccountId',v_to.data->>'accountId'),false);
  perform public.erp_post_cloud_cash_transaction(p_company_id,jsonb_build_object('id',gen_random_uuid()::text,'voucherNumber',v_number||'-IN','type','receipt','category','تحويل بين الصناديق','amount',p_target_amount,'currency',v_to.data->>'currency','transactionDate',p_transfer_date,'partyType','cash_account','partyId',p_from_cash_account_id,'partyName',v_from.data->>'name','paymentMethod','bank_transfer','referenceType','cash_transfer','referenceId',v_transfer,'notes',p_notes,'createdAt',v_now,'cashAccountId',p_to_cash_account_id,'counterAccountId',v_from.data->>'accountId'),false);
end $$;

create or replace function public.erp_cloud_cash_account_balances(p_company_id uuid)
returns table(cash_account_id text,balance numeric) language sql security definer set search_path=public as $$
  select ca.id, coalesce((ca.data->>'openingBalance')::numeric,0)+coalesce(sum(case when ct.data->>'type'='receipt' then (ct.data->>'amount')::numeric else -(ct.data->>'amount')::numeric end),0)
  from public.erp_cash_accounts ca left join public.erp_cash_transactions ct on ct.company_id=ca.company_id and not ct.is_deleted and ct.data->>'cashAccountId'=ca.id
  where ca.company_id=p_company_id and not ca.is_deleted and public.is_active_company_member(p_company_id)
  group by ca.id,ca.data;
$$;

create or replace function public.erp_cloud_cash_currency_summary(p_company_id uuid,p_currency text)
returns jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object('receipts',coalesce(sum(case when data->>'type'='receipt' then (data->>'amount')::numeric else 0 end),0),'payments',coalesce(sum(case when data->>'type'='payment' then (data->>'amount')::numeric else 0 end),0))
  from public.erp_cash_transactions where company_id=p_company_id and not is_deleted and data->>'currency'=p_currency and public.is_active_company_member(p_company_id);
$$;

create or replace function public.erp_save_cloud_installment(p_company_id uuid,p_installment jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_installment->>'id'; v_sale text:=p_installment->>'saleId'; v_amount numeric:=coalesce((p_installment->>'amount')::numeric,-1); v_paid numeric:=coalesce((p_installment->>'paidAmount')::numeric,-1); v_remaining numeric:=coalesce((p_installment->>'remainingAmount')::numeric,-1);
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(v_sale,'')='' or v_amount<0 or v_paid<0 or v_remaining<0 or abs(v_paid+v_remaining-v_amount)>0.01 then raise exception 'بيانات القسط غير صحيحة'; end if;
  if not exists(select 1 from public.erp_sales where company_id=p_company_id and id=v_sale and not is_deleted) then raise exception 'فاتورة البيع غير موجودة'; end if;
  insert into public.erp_installments(company_id,id,data,created_by,updated_by) values(p_company_id,v_id,p_installment||jsonb_build_object('updatedAt',now()),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now(),updated_by=auth.uid();
end $$;

create or replace function public.erp_delete_cloud_installment(p_company_id uuid,p_installment_id text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  update public.erp_installments set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=p_installment_id and not is_deleted;
end $$;

create or replace function public.erp_cloud_installment_totals(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object('total',coalesce(sum((data->>'amount')::numeric),0),'remaining',coalesce(sum((data->>'remainingAmount')::numeric),0))
  from public.erp_installments where company_id=p_company_id and not is_deleted and public.is_active_company_member(p_company_id);
$$;

grant execute on function public.erp_save_cloud_cash_account(uuid,jsonb),public.erp_delete_cloud_cash_account(uuid,text),public.erp_post_cloud_cash_transaction(uuid,jsonb,boolean),public.erp_delete_cloud_cash_transaction(uuid,text),public.erp_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text),public.erp_cloud_cash_account_balances(uuid),public.erp_cloud_cash_currency_summary(uuid,text),public.erp_save_cloud_installment(uuid,jsonb),public.erp_delete_cloud_installment(uuid,text),public.erp_cloud_installment_totals(uuid) to authenticated;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['erp_cash_accounts','erp_cash_transactions','erp_cash_transfers','erp_journal_entries','erp_journal_lines'] LOOP
    BEGIN EXECUTE format('alter publication supabase_realtime add table public.%I',t); EXCEPTION WHEN duplicate_object THEN NULL; END;
  END LOOP;
END $$;

commit;
