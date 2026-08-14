begin;

create or replace function public.erp_r68_stamp_maintenance_payment_family()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_r68_stamp_payment_envelope(
    new.company_id,
    coalesce(new.payment_payload,'{}'::jsonb)||jsonb_build_object(
      'paymentId',new.id,'paymentKey',new.payment_key,
      'cashTransactionId',new.cash_transaction_id,
      'journalEntryId',new.journal_entry_id
    )
  );
  return new;
end;
$$;

drop trigger if exists erp_r68_stamp_maintenance_payment_family
  on public.erp_maintenance_payments;
create trigger erp_r68_stamp_maintenance_payment_family
after insert or update of payment_payload,payment_key,cash_transaction_id,
  journal_entry_id on public.erp_maintenance_payments
for each row execute function public.erp_r68_stamp_maintenance_payment_family();

do $$
declare v_payment record;
begin
  for v_payment in
    select company_id,id,payment_key,cash_transaction_id,journal_entry_id,
           payment_payload
    from public.erp_maintenance_payments
  loop
    perform public.erp_r68_stamp_payment_envelope(
      v_payment.company_id,
      coalesce(v_payment.payment_payload,'{}'::jsonb)||jsonb_build_object(
        'paymentId',v_payment.id,'paymentKey',v_payment.payment_key,
        'cashTransactionId',v_payment.cash_transaction_id,
        'journalEntryId',v_payment.journal_entry_id
      )
    );
  end loop;
end;
$$;

revoke all on function public.erp_r68_stamp_maintenance_payment_family()
  from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
