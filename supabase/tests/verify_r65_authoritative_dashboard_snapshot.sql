\set ON_ERROR_STOP on

begin;
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub','5dfff075-0653-4918-bcce-293eea5e68d6',
    'role','authenticated'
  )::text,
  true
);
set local role authenticated;

do $$
declare
  v_company constant uuid:='11111111-1111-4111-8111-111111111111';
  v_snapshot jsonb;
  v_expected numeric;
  v_currency text;
begin
  v_snapshot:=public.erp_r65_get_authoritative_dashboard_snapshot(
    v_company,null,'2026-08-14'::date
  );

  foreach v_currency in array array['USD','IQD'] loop
    if not (v_snapshot->'totalSalesByCurrency' ? v_currency)
       or not (v_snapshot->'totalPurchasesByCurrency' ? v_currency)
       or not (v_snapshot->'totalReceivablesByCurrency' ? v_currency)
       or not (v_snapshot->'totalPayablesByCurrency' ? v_currency)
       or not (v_snapshot->'cashBalanceByCurrency' ? v_currency)
       or not (v_snapshot->'inventoryValueByCurrency' ? v_currency)
       or not (v_snapshot->'netProfitByCurrency' ? v_currency) then
      raise exception 'r65_missing_currency_bucket:%',v_currency;
    end if;
  end loop;

  select coalesce(sum(public.erp_try_numeric(d.payload->>'totalAmount',0)),0)
  into v_expected from public.erp_commercial_workflow_documents d
  where d.company_id=v_company and d.module='sales' and d.document_type='invoice'
    and d.status='approved' and not d.is_deleted
    and upper(btrim(d.payload->>'currency'))='USD'
    and (coalesce(d.effective_at,d.created_at) at time zone 'Asia/Baghdad')::date<='2026-08-14';
  if (v_snapshot->'totalSalesByCurrency'->>'USD')::numeric<>v_expected then
    raise exception 'r65_sales_invoice_reconciliation_failed';
  end if;

  select coalesce(sum(public.erp_try_numeric(d.payload->>'totalAmount',0)),0)
  into v_expected from public.erp_commercial_workflow_documents d
  where d.company_id=v_company and d.module='purchases' and d.document_type='invoice'
    and d.status='approved' and not d.is_deleted
    and upper(btrim(d.payload->>'currency'))='USD'
    and (coalesce(d.effective_at,d.created_at) at time zone 'Asia/Baghdad')::date<='2026-08-14';
  if (v_snapshot->'totalPurchasesByCurrency'->>'USD')::numeric<>v_expected then
    raise exception 'r65_purchase_invoice_reconciliation_failed';
  end if;

  select coalesce(sum(greatest(public.erp_try_numeric(d.payload->>'remainingAmount',0),0)),0)
  into v_expected from public.erp_commercial_workflow_documents d
  where d.company_id=v_company and d.module='purchases' and d.document_type='invoice'
    and d.status='approved' and not d.is_deleted
    and upper(btrim(d.payload->>'currency'))='USD';
  if (v_snapshot->'totalPayablesByCurrency'->>'USD')::numeric<>v_expected then
    raise exception 'r65_payables_reconciliation_failed';
  end if;

  select coalesce(sum(l.remaining_quantity*l.unit_cost),0) into v_expected
  from public.erp_inventory_cost_layers l
  where l.company_id=v_company and l.status in ('active','consumed')
    and l.remaining_quantity>0 and l.item_type in ('product','car') and l.currency='USD';
  if (v_snapshot->'inventoryValueByCurrency'->>'USD')::numeric<>v_expected then
    raise exception 'r65_fifo_inventory_reconciliation_failed';
  end if;

  select coalesce(sum(balance),0) into v_expected from (
    select public.erp_try_numeric(
      coalesce(a.data->>'openingBalance',a.data->>'opening_balance'),0
    )+coalesce(sum(case
      when lower(coalesce(t.data->>'type','')) in
        ('receipt','income','in','cash_in','customer_receipt','transfer_in')
        then abs(public.erp_try_numeric(t.data->>'amount',0))
      when lower(coalesce(t.data->>'type','')) in
        ('payment','expense','out','cash_out','supplier_payment','transfer_out')
        then -abs(public.erp_try_numeric(t.data->>'amount',0))
      else 0 end),0) balance
    from public.erp_cash_accounts a
    left join public.erp_cash_transactions t on t.company_id=a.company_id
      and not t.is_deleted
      and coalesce(t.data->>'cashAccountId',t.data->>'cash_account_id')=a.id
    where a.company_id=v_company and not a.is_deleted
      and upper(a.data->>'currency')='USD'
    group by a.id,a.data
  ) q;
  if (v_snapshot->'cashBalanceByCurrency'->>'USD')::numeric<>v_expected then
    raise exception 'r65_cash_reconciliation_failed';
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_snapshot->'recentDocuments') d
    where coalesce(d->>'reference','')='' or coalesce(d->>'status','')=''
  ) then raise exception 'r65_recent_document_identity_failed'; end if;

  begin
    perform public.erp_r65_get_authoritative_dashboard_snapshot(
      '22222222-2222-4222-8222-222222222222',null,'2026-08-14'
    );
    raise exception 'r65_cross_company_call_was_not_denied';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.erp_r65_get_authoritative_dashboard_snapshot(
      v_company,'2026-08-15','2026-08-14'
    );
    raise exception 'r65_invalid_date_range_was_not_denied';
  exception when sqlstate '22023' then null;
  end;
end;
$$;

rollback;
\echo 'R65 authoritative Dashboard snapshot PASS'
