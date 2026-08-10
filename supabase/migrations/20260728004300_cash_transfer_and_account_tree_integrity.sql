begin;

-- 17.55: cash-transfer concurrency/balance protection and chart-of-accounts
-- hierarchy integrity. PostgreSQL remains the authoritative validation layer.

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
  v_from_ledger text;
  v_to_ledger text;
  v_from_balance numeric:=0;
  v_clearing_id text:='system-fx-clearing';
  v_clearing_code text:='FX-CLEARING';
  v_existing_clearing record;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if p_from_cash_account_id=p_to_cash_account_id or p_source_amount<=0 or
     p_target_amount<=0 or p_exchange_rate<=0 or p_transfer_date is null then
    raise exception 'بيانات التحويل غير صحيحة';
  end if;

  if abs(p_target_amount-(p_source_amount*p_exchange_rate)) >
     greatest(0.01,abs(p_source_amount*p_exchange_rate)*0.000001) then
    raise exception 'المبلغ الداخل لا يطابق المبلغ الخارج مضروبًا في سعر التحويل';
  end if;

  -- Deterministic company/account lock prevents reverse concurrent transfers
  -- from deadlocking or spending the same balance twice.
  perform pg_advisory_xact_lock(
    hashtextextended(
      p_company_id::text||':'||least(p_from_cash_account_id,p_to_cash_account_id)||':'||
      greatest(p_from_cash_account_id,p_to_cash_account_id),0
    )
  );

  select * into v_from from public.erp_cash_accounts
  where company_id=p_company_id and id=p_from_cash_account_id and not is_deleted for update;
  if not found or not public.erp_try_boolean(coalesce(v_from.data->>'isActive',v_from.data->>'is_active'),'true') then
    raise exception 'صندوق المصدر غير موجود أو غير فعال';
  end if;

  select * into v_to from public.erp_cash_accounts
  where company_id=p_company_id and id=p_to_cash_account_id and not is_deleted for update;
  if not found or not public.erp_try_boolean(coalesce(v_to.data->>'isActive',v_to.data->>'is_active'),'true') then
    raise exception 'صندوق الوجهة غير موجود أو غير فعال';
  end if;

  v_from_currency:=upper(trim(coalesce(v_from.data->>'currency','')));
  v_to_currency:=upper(trim(coalesce(v_to.data->>'currency','')));
  v_from_ledger:=nullif(trim(coalesce(v_from.data->>'accountId',v_from.data->>'account_id','')),'');
  v_to_ledger:=nullif(trim(coalesce(v_to.data->>'accountId',v_to.data->>'account_id','')),'');
  if v_from_currency='' or v_to_currency='' then raise exception 'عملة أحد الصندوقين غير معرفة'; end if;
  if v_from_ledger is null or v_to_ledger is null then raise exception 'أحد الصندوقين غير مرتبط بحساب محاسبي'; end if;
  if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_from_ledger and is_active and account_type='asset') or
     not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_to_ledger and is_active and account_type='asset') then
    raise exception 'الحساب المحاسبي لأحد الصندوقين غير موجود أو غير فعال';
  end if;

  select
    public.erp_try_numeric(coalesce(v_from.data->>'openingBalance',v_from.data->>'opening_balance'),0)+
    coalesce(sum(case
      when ct.data->>'type'='receipt' then public.erp_try_numeric(ct.data->>'amount',0)
      when ct.data->>'type'='payment' then -public.erp_try_numeric(ct.data->>'amount',0)
      else 0 end),0)
  into v_from_balance
  from public.erp_cash_transactions ct
  where ct.company_id=p_company_id and not ct.is_deleted
    and ct.data->>'cashAccountId'=p_from_cash_account_id;

  if v_from_balance < p_source_amount then
    raise exception 'رصيد صندوق المصدر غير كافٍ لإتمام التحويل';
  end if;

  if v_from_currency=v_to_currency then
    if abs(p_source_amount-p_target_amount)>0.0001 or abs(p_exchange_rate-1)>0.0001 then
      raise exception 'التحويل داخل العملة نفسها يجب أن يكون بالقيمة نفسها وسعر صرف 1';
    end if;
    v_from_counter:=v_to_ledger;
    v_to_counter:=v_from_ledger;
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

create or replace function public.erp_delete_cloud_cash_transfer(
  p_company_id uuid,p_transfer_id text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_now timestamptz:=now();
  v_transaction record;
  v_movement_count integer;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if not exists(
    select 1 from public.erp_cash_transfers
    where company_id=p_company_id and id=p_transfer_id and not is_deleted for update
  ) then raise exception 'لم يتم العثور على التحويل المطلوب'; end if;

  select count(*) into v_movement_count
  from public.erp_cash_transactions
  where company_id=p_company_id and not is_deleted
    and lower(coalesce(data->>'referenceType',''))='cash_transfer'
    and data->>'referenceId'=p_transfer_id;
  if v_movement_count<>2 then
    raise exception 'تعذر حذف التحويل: عدد حركات الصندوق المرتبطة غير مكتمل';
  end if;

  for v_transaction in
    select id,data->>'journalEntryId' as journal_id
    from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'referenceType',''))='cash_transfer'
      and data->>'referenceId'=p_transfer_id
    for update
  loop
    if nullif(v_transaction.journal_id,'') is null or not exists(
      select 1 from public.erp_journal_entries
      where company_id=p_company_id and id=v_transaction.journal_id and not is_deleted
    ) then raise exception 'تعذر حذف التحويل: القيد المحاسبي المرتبط غير موجود'; end if;

    update public.erp_journal_lines
      set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'entryId'=v_transaction.journal_id;
    update public.erp_journal_entries
      set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_transaction.journal_id and not is_deleted;
    update public.erp_cash_transactions
      set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_transaction.id and not is_deleted;
  end loop;

  update public.erp_cash_transfers
    set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=p_transfer_id and not is_deleted;
end $$;

create or replace function public.erp_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=btrim(coalesce(p_account->>'id',''));
  v_parent text:=nullif(btrim(coalesce(p_account->>'parentId',p_account->>'parent_id','')),'');
  v_code text:=btrim(coalesce(p_account->>'code',''));
  v_name text:=btrim(coalesce(p_account->>'name',''));
  v_currency text:=upper(coalesce(nullif(btrim(p_account->>'currency'),''),'USD'));
  v_type text:=lower(btrim(coalesce(p_account->>'type',p_account->>'account_type','')));
  v_parent_currency text;
  v_parent_type text;
  v_existing public.erp_accounts%rowtype;
  v_active boolean:=public.erp_try_boolean(coalesce(p_account->>'isActive',p_account->>'is_active'),'true');
  v_opening numeric:=public.erp_try_numeric(coalesce(p_account->>'openingBalance',p_account->>'opening_balance'),0);
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_id='' or v_code='' or v_name='' then raise exception 'بيانات الحساب غير مكتملة'; end if;
  if v_type not in ('asset','liability','equity','revenue','expense') then raise exception 'نوع الحساب غير صحيح'; end if;
  if v_currency not in ('USD','IQD','MULTI') then raise exception 'عملة الحساب غير صحيحة'; end if;

  select * into v_existing from public.erp_accounts
  where organization_id=p_company_id and account_id=v_id for update;
  if p_require_existing and not found then raise exception 'الحساب غير موجود'; end if;

  if not v_active and exists(
    select 1 from public.erp_accounts
    where organization_id=p_company_id and parent_account_id=v_id and is_active
  ) then raise exception 'لا يمكن تعطيل حساب يحتوي على حسابات فرعية فعالة'; end if;

  if v_existing.account_id is not null and
     (upper(v_existing.currency)<>v_currency or v_existing.account_type<>v_type) and exists(
       select 1 from public.erp_journal_lines
       where company_id=p_company_id and not is_deleted and data->>'accountId'=v_id
     ) then raise exception 'لا يمكن تغيير نوع أو عملة حساب مرتبط بقيود'; end if;

  if exists(
    select 1 from public.erp_accounts
    where organization_id=p_company_id and lower(code)=lower(v_code)
      and account_id<>v_id and is_active
  ) then raise exception 'رمز الحساب مستخدم مسبقًا'; end if;

  if v_parent=v_id then raise exception 'لا يمكن جعل الحساب أباً لنفسه'; end if;
  if v_parent is not null then
    select upper(currency),account_type into v_parent_currency,v_parent_type
    from public.erp_accounts
    where organization_id=p_company_id and account_id=v_parent and is_active;
    if v_parent_currency is null then raise exception 'الحساب الأب غير موجود أو غير فعال'; end if;
    if v_parent_type<>v_type then raise exception 'نوع الحساب الفرعي يجب أن يطابق نوع الحساب الأب'; end if;
    if v_parent_currency<>v_currency and v_parent_currency<>'MULTI' then
      raise exception 'عملة الحساب الفرعي يجب أن تطابق عملة الحساب الأب';
    end if;
    if exists(
      select 1 from public.erp_journal_lines
      where company_id=p_company_id and not is_deleted and data->>'accountId'=v_parent
    ) then raise exception 'لا يمكن إضافة حساب فرعي تحت حساب مستخدم في قيود؛ أنشئ حساباً تجميعياً'; end if;
    if exists(
      with recursive descendants as (
        select account_id from public.erp_accounts
        where organization_id=p_company_id and parent_account_id=v_id
        union all
        select a.account_id from public.erp_accounts a
        join descendants d on a.parent_account_id=d.account_id
        where a.organization_id=p_company_id
      ) select 1 from descendants where account_id=v_parent
    ) then raise exception 'لا يمكن نقل الحساب تحت أحد حساباته الفرعية'; end if;
  end if;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,
    currency,opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values(
    p_company_id,v_id,v_code,v_name,v_type,v_parent,v_currency,v_opening,
    v_active,now(),now(),auth.uid()
  ) on conflict(organization_id,account_id) do update set
    code=excluded.code,name=excluded.name,account_type=excluded.account_type,
    parent_account_id=excluded.parent_account_id,currency=excluded.currency,
    opening_balance=excluded.opening_balance,is_active=excluded.is_active,
    source_updated_at=now(),synced_at=now(),synced_by=auth.uid();
end $$;

create or replace function public.erp_delete_cloud_ledger_account(
  p_company_id uuid,p_account_id text
) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  perform 1 from public.erp_accounts
  where organization_id=p_company_id and account_id=p_account_id for update;
  if not found then raise exception 'الحساب غير موجود'; end if;
  if exists(
    select 1 from public.erp_accounts
    where organization_id=p_company_id and parent_account_id=p_account_id
  ) then raise exception 'لا يمكن حذف حساب يحتوي على حسابات فرعية، بما فيها الحسابات المعطلة'; end if;
  if exists(
    select 1 from public.erp_journal_lines
    where company_id=p_company_id and not is_deleted and data->>'accountId'=p_account_id
  ) then raise exception 'لا يمكن حذف حساب مرتبط بقيود يومية'; end if;
  if exists(
    select 1 from public.erp_cash_accounts
    where company_id=p_company_id and not is_deleted
      and coalesce(data->>'accountId',data->>'account_id')=p_account_id
  ) then raise exception 'لا يمكن حذف حساب مرتبط بصندوق مالي'; end if;
  update public.erp_accounts set is_active=false,source_updated_at=now(),synced_at=now(),synced_by=auth.uid()
  where organization_id=p_company_id and account_id=p_account_id;
end $$;

grant execute on function public.erp_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated;
grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text) to authenticated;
grant execute on function public.erp_save_cloud_ledger_account(uuid,jsonb,boolean) to authenticated;
grant execute on function public.erp_delete_cloud_ledger_account(uuid,text) to authenticated;

commit;
