begin;

-- Final exchange-rate consistency contract.

-- Cross-currency cash transfers must not use the destination cash ledger as the
-- counter account of the source voucher (or vice versa), because each ledger
-- account has its own currency. Route both sides through a company-scoped MULTI
-- currency clearing account while preserving direct cash-to-cash posting for
-- same-currency transfers.
create or replace function public.erp_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric,
  p_transfer_date timestamptz,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_from public.erp_cash_accounts%rowtype;
  v_to public.erp_cash_accounts%rowtype;
  v_transfer text:=gen_random_uuid()::text;
  v_number text:='TR-'||floor(extract(epoch from clock_timestamp())*1000000)::bigint;
  v_now timestamptz:=now();
  v_from_currency text;
  v_to_currency text;
  v_from_counter text;
  v_to_counter text;
  v_clearing_id text:='system-fx-clearing';
  v_clearing_code text:='FX-CLEARING';
  v_existing_clearing record;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if p_from_cash_account_id=p_to_cash_account_id or p_source_amount<=0 or p_target_amount<=0 or p_exchange_rate<=0 or p_transfer_date is null then
    raise exception 'بيانات التحويل غير صحيحة';
  end if;

  if abs(p_target_amount-(p_source_amount*p_exchange_rate)) > greatest(0.01,abs(p_source_amount*p_exchange_rate)*0.000001) then
    raise exception 'المبلغ الداخل لا يطابق المبلغ الخارج مضروبًا في سعر التحويل';
  end if;

  select * into v_from from public.erp_cash_accounts
  where company_id=p_company_id and id=p_from_cash_account_id and not is_deleted for update;
  if not found or not coalesce((v_from.data->>'isActive')::boolean,true) then raise exception 'صندوق المصدر غير موجود أو غير فعال'; end if;

  select * into v_to from public.erp_cash_accounts
  where company_id=p_company_id and id=p_to_cash_account_id and not is_deleted for update;
  if not found or not coalesce((v_to.data->>'isActive')::boolean,true) then raise exception 'صندوق الوجهة غير موجود أو غير فعال'; end if;

  v_from_currency:=upper(coalesce(v_from.data->>'currency',''));
  v_to_currency:=upper(coalesce(v_to.data->>'currency',''));
  if v_from_currency='' or v_to_currency='' then raise exception 'عملة أحد الصندوقين غير معرفة'; end if;

  if v_from_currency=v_to_currency then
    if abs(p_source_amount-p_target_amount)>0.0001 or abs(p_exchange_rate-1)>0.0001 then
      raise exception 'التحويل داخل العملة نفسها يجب أن يكون بالقيمة نفسها وسعر صرف 1';
    end if;
    v_from_counter:=v_to.data->>'accountId';
    v_to_counter:=v_from.data->>'accountId';
  else
    select account_id,currency,is_active into v_existing_clearing
    from public.erp_accounts
    where organization_id=p_company_id and lower(code)=lower(v_clearing_code)
    limit 1;

    if v_existing_clearing.account_id is not null then
      if upper(coalesce(v_existing_clearing.currency,''))<>'MULTI' then
        raise exception 'رمز FX-CLEARING مستخدم لحساب غير متعدد العملات';
      end if;
      v_clearing_id:=v_existing_clearing.account_id;
      update public.erp_accounts set is_active=true,synced_at=v_now,synced_by=auth.uid()
      where organization_id=p_company_id and account_id=v_clearing_id;
    else
      insert into public.erp_accounts(
        organization_id,account_id,code,name,account_type,parent_account_id,currency,
        opening_balance,is_active,source_updated_at,synced_at,synced_by
      ) values (
        p_company_id,v_clearing_id,v_clearing_code,
        'Foreign currency cash transfer clearing / تسوية تحويلات الصناديق متعددة العملات',
        'asset',null,'MULTI',0,true,v_now,v_now,auth.uid()
      );
    end if;
    v_from_counter:=v_clearing_id;
    v_to_counter:=v_clearing_id;
  end if;

  insert into public.erp_cash_transfers(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_transfer,jsonb_build_object(
    'id',v_transfer,'transferNumber',v_number,
    'fromAccountId',p_from_cash_account_id,'toAccountId',p_to_cash_account_id,
    'sourceAmount',p_source_amount,'sourceCurrency',v_from_currency,
    'targetAmount',p_target_amount,'targetCurrency',v_to_currency,
    'exchangeRate',p_exchange_rate,'transferDate',p_transfer_date,
    'notes',p_notes,'createdAt',v_now
  ),auth.uid(),auth.uid());

  perform public.erp_post_cloud_cash_transaction(p_company_id,jsonb_build_object(
    'id',gen_random_uuid()::text,'voucherNumber',v_number||'-OUT','type','payment',
    'category','تحويل بين الصناديق','amount',p_source_amount,'currency',v_from_currency,
    'transactionDate',p_transfer_date,'partyType','cash_account','partyId',p_to_cash_account_id,
    'partyName',v_to.data->>'name','paymentMethod','bank_transfer','referenceType','cash_transfer',
    'referenceId',v_transfer,'notes',p_notes,'createdAt',v_now,
    'cashAccountId',p_from_cash_account_id,'counterAccountId',v_from_counter
  ),false);

  perform public.erp_post_cloud_cash_transaction(p_company_id,jsonb_build_object(
    'id',gen_random_uuid()::text,'voucherNumber',v_number||'-IN','type','receipt',
    'category','تحويل بين الصناديق','amount',p_target_amount,'currency',v_to_currency,
    'transactionDate',p_transfer_date,'partyType','cash_account','partyId',p_from_cash_account_id,
    'partyName',v_from.data->>'name','paymentMethod','bank_transfer','referenceType','cash_transfer',
    'referenceId',v_transfer,'notes',p_notes,'createdAt',v_now,
    'cashAccountId',p_to_cash_account_id,'counterAccountId',v_to_counter
  ),false);
end $$;

grant execute on function public.erp_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated;

commit;
