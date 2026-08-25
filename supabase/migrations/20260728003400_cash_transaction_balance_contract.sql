begin;

-- Final cash voucher contract: a receipt increases the selected cashbox and a
-- payment decreases it, regardless of which valid counter ledger account is used.
create or replace function public.erp_post_cloud_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=p_transaction->>'id'; v_cash_id text:=p_transaction->>'cashAccountId';
  v_counter_id text:=p_transaction->>'counterAccountId'; v_type text:=lower(p_transaction->>'type');
  v_currency text:=upper(coalesce(p_transaction->>'currency',''));
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
  if upper(coalesce(v_cash.data->>'currency',''))<>v_currency then raise exception 'عملة السند لا تطابق عملة الصندوق'; end if;
  select account_id,code,name,currency into v_cash_account from public.erp_accounts
    where organization_id=p_company_id and account_id=v_cash.data->>'accountId' and is_active;
  select account_id,code,name,currency into v_counter from public.erp_accounts
    where organization_id=p_company_id and account_id=v_counter_id and is_active;
  if v_cash_account.account_id is null or v_counter.account_id is null then raise exception 'الحساب المحاسبي غير موجود أو غير فعال'; end if;
  if v_cash_account.account_id=v_counter.account_id then raise exception 'الحساب المقابل يجب أن يختلف عن حساب الصندوق'; end if;
  if upper(coalesce(v_cash_account.currency,'')) not in (v_currency,'MULTI') then raise exception 'عملة حساب الصندوق لا تطابق عملة السند'; end if;
  if upper(coalesce(v_counter.currency,'')) not in (v_currency,'MULTI') then raise exception 'عملة الحساب المقابل لا تطابق عملة السند'; end if;
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
  v_payload:=p_transaction||jsonb_build_object('type',v_type,'currency',v_currency,'journalEntryId',v_journal_id,'updatedAt',v_now);
  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,v_payload,auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=v_now,updated_by=auth.uid();
  if v_type='receipt' then v_cash_debit:=v_amount; else v_cash_credit:=v_amount; end if;
  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_journal_id,jsonb_build_object(
    'id',v_journal_id,'entryNumber','CASH-'||(p_transaction->>'voucherNumber'),
    'entryDate',p_transaction->>'transactionDate','description',case when v_type='receipt' then 'قبض نقدي' else 'صرف نقدي' end||' - '||coalesce(p_transaction->>'category',''),
    'currency',v_currency,'referenceType','cash_transaction','referenceId',v_id,
    'totalDebit',v_amount,'totalCredit',v_amount,'status','posted','createdAt',v_now),auth.uid(),auth.uid());
  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_cash_account.account_id,'accountCode',v_cash_account.code,'accountName',v_cash_account.name,'debit',v_cash_debit,'credit',v_cash_credit,'description',coalesce(p_transaction->>'notes','')),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_counter.account_id,'accountCode',v_counter.code,'accountName',v_counter.name,'debit',v_cash_credit,'credit',v_cash_debit,'description',coalesce(p_transaction->>'notes','')),auth.uid(),auth.uid());
end $$;

grant execute on function public.erp_post_cloud_cash_transaction(uuid,jsonb,boolean) to authenticated;
commit;
