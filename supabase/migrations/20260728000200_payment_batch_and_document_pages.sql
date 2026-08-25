begin;

create or replace function public.erp_list_cloud_settlement_accounts(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'id',a.account_id,
    'code',a.code,
    'name',coalesce(a.name,a.code),
    'nameAr',coalesce(a.name,a.code),
    'nameEn',coalesce(a.name,a.code),
    'type',a.account_type
  )
  from public.erp_accounts a
  where a.organization_id=p_company_id
    and a.is_active
    and public.erp_is_company_member(p_company_id)
  order by a.code,a.name;
$$;

create or replace function public.erp_apply_cloud_workflow_invoice_payment_batch(
  p_company_id uuid,
  p_invoice_id uuid,
  p_module text,
  p_payments jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_payment jsonb;
  v_mode text;
  v_settlement_account text;
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_last jsonb;
  v_journal_id text;
  v_payment_id text;
  v_results jsonb:='[]'::jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  if p_payments is null or jsonb_typeof(p_payments)<>'array' or jsonb_array_length(p_payments)=0 then
    raise exception 'يجب إضافة دفعة واحدة على الأقل';
  end if;

  select * into v_doc
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module
    and document_type='invoice' and status='approved' and not is_deleted
  for update;
  if not found then raise exception 'الفاتورة المصدقة غير موجودة'; end if;

  for v_payment in select value from jsonb_array_elements(p_payments) loop
    v_mode:=lower(btrim(coalesce(v_payment->>'settlementMode','partial')));
    if v_mode not in ('partial','full','settlement') then
      raise exception 'نوع الدفعة غير مدعوم';
    end if;

    if v_mode='settlement' then
      begin
        v_settlement_account:=btrim(coalesce(v_payment->>'settlementAccountId',''));
      exception when others then
        raise exception 'حساب التسوية غير صحيح';
      end;
      if v_settlement_account='' then raise exception 'حساب التسوية غير صحيح'; end if;
      perform 1 from public.erp_accounts
      where organization_id=p_company_id and account_id=v_settlement_account and is_active
      for share;
      if not found then raise exception 'حساب التسوية غير موجود أو غير فعال'; end if;
    else
      v_settlement_account:=null;
    end if;

    if v_mode in ('full','settlement') then
      v_payment:=v_payment||jsonb_build_object(
        'invoiceAmount',public.erp_try_numeric(v_doc.payload->>'remainingAmount',0)
      );
    end if;

    perform public.erp_apply_cloud_workflow_invoice_payment(
      p_company_id,
      p_invoice_id,
      p_module,
      v_payment || jsonb_build_object(
        'settlementMode',case when v_mode='settlement' then 'full_fx' else 'partial' end
      )
    );

    select * into v_doc
    from public.erp_commercial_workflow_documents
    where company_id=p_company_id and id=p_invoice_id and not is_deleted
    for update;
    v_last:=coalesce(v_doc.payload->'payments'->-1,'{}'::jsonb);
    v_journal_id:=nullif(v_last->>'journalEntryId','');
    v_payment_id:=nullif(v_last->>'paymentId','');

    if v_mode='settlement' then
      if v_journal_id is null or v_payment_id is null then
        raise exception 'تعذر تحديد قيد دفعة التسوية';
      end if;
      update public.erp_journal_lines jl
      set data=jsonb_set(jl.data,'{accountId}',to_jsonb(v_settlement_account),true)
               ||jsonb_build_object('description','تسوية فاتورة','settlementPaymentId',v_payment_id),
          updated_at=now(),updated_by=auth.uid()
      where jl.company_id=p_company_id and not jl.is_deleted
        and jl.data->>'entryId'=v_journal_id
        and jl.data->>'accountId' in (
          select account_id::text from public.erp_accounts
          where organization_id=p_company_id and code in ('4200','5300')
        );

      update public.erp_commercial_workflow_documents
      set payload=jsonb_set(
        payload,
        array['payments',(jsonb_array_length(payload->'payments')-1)::text],
        v_last||jsonb_build_object(
          'settlementMode','settlement',
          'settlementAccountId',v_settlement_account
        ),
        true
      ),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=p_invoice_id;
      v_last:=v_last||jsonb_build_object(
        'settlementMode','settlement',
        'settlementAccountId',v_settlement_account
      );
    elsif v_mode='full' then
      update public.erp_commercial_workflow_documents
      set payload=jsonb_set(
        payload,
        array['payments',(jsonb_array_length(payload->'payments')-1)::text],
        v_last||jsonb_build_object('settlementMode','full'),
        true
      ),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=p_invoice_id;
      v_last:=v_last||jsonb_build_object('settlementMode','full');
    end if;

    v_results:=v_results||jsonb_build_array(v_last);
  end loop;
  return v_results;
end;
$$;

create or replace function public.erp_pay_cloud_sales_workflow_invoice_batch(
  p_company_id uuid,p_invoice_id uuid,p_payments jsonb
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_apply_cloud_workflow_invoice_payment_batch(
    p_company_id,p_invoice_id,'sales',p_payments
  )
$$;

create or replace function public.erp_pay_cloud_purchase_workflow_invoice_batch(
  p_company_id uuid,p_invoice_id uuid,p_payments jsonb
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_apply_cloud_workflow_invoice_payment_batch(
    p_company_id,p_invoice_id,'purchases',p_payments
  )
$$;

grant execute on function public.erp_list_cloud_settlement_accounts(uuid) to authenticated;
grant execute on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.erp_pay_cloud_sales_workflow_invoice_batch(uuid,uuid,jsonb) to authenticated;
grant execute on function public.erp_pay_cloud_purchase_workflow_invoice_batch(uuid,uuid,jsonb) to authenticated;

commit;
