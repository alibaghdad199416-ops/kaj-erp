-- Quality Line ERP v17.6.0 P7
-- PostgreSQL-authoritative payment settlement calculation.

create table if not exists public.erp_payment_settlement_plans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  command_id uuid not null unique references public.erp_financial_commands(id) on delete cascade,
  module text not null check (module in ('sales', 'purchases')),
  workflow_id text not null,
  invoice_id text not null,
  invoice_currency text not null check (invoice_currency in ('USD', 'IQD')),
  payment_currency text not null check (payment_currency in ('USD', 'IQD')),
  settlement_mode text not null check (settlement_mode in ('partial', 'full_fx')),
  previous_remaining numeric(20,4) not null,
  applied_invoice_amount numeric(20,4) not null,
  cash_amount numeric(20,4) not null,
  exchange_rate numeric(20,8) not null,
  expected_cash_amount numeric(20,4) not null,
  actual_invoice_equivalent numeric(20,4) not null,
  exchange_difference numeric(20,4) not null,
  next_remaining numeric(20,4) not null,
  next_payment_status text not null check (next_payment_status in ('partial', 'paid')),
  journal_plan jsonb not null,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists erp_payment_settlement_plans_org_invoice_idx
  on public.erp_payment_settlement_plans(organization_id, module, invoice_id, created_at desc);

alter table public.erp_payment_settlement_plans enable row level security;

drop policy if exists erp_payment_settlement_plans_select on public.erp_payment_settlement_plans;
create policy erp_payment_settlement_plans_select
on public.erp_payment_settlement_plans for select to authenticated
using (public.erp_is_active_member(organization_id));

revoke insert, update, delete on public.erp_payment_settlement_plans from anon, authenticated;
grant select on public.erp_payment_settlement_plans to authenticated;

create or replace function public.erp_prepare_payment_settlement(
  p_command_id uuid,
  p_invoice_id text,
  p_invoice_currency text,
  p_payment_currency text,
  p_previous_remaining numeric,
  p_requested_invoice_amount numeric,
  p_cash_amount numeric,
  p_exchange_rate numeric,
  p_settlement_mode text,
  p_cash_account_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_command public.erp_financial_commands%rowtype;
  v_applied numeric(20,4);
  v_expected numeric(20,4);
  v_actual numeric(20,4);
  v_difference numeric(20,4);
  v_next numeric(20,4);
  v_status text;
  v_tolerance numeric(20,4);
  v_plan jsonb;
  v_existing public.erp_payment_settlement_plans%rowtype;
  v_aggregate jsonb;
  v_cloud_remaining numeric(20,4);
  v_cloud_currency text;
  v_cloud_invoice_id text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;

  select * into v_command
  from public.erp_financial_commands
  where id = p_command_id
  for update;

  if not found then raise exception 'financial_command_not_found'; end if;
  if not public.erp_is_active_member(v_command.organization_id) then
    raise exception 'permission_denied';
  end if;
  if v_command.status = 'aborted' then raise exception 'financial_command_aborted'; end if;
  if v_command.event_type <> 'invoice_payment_posted' then
    raise exception 'invalid_financial_command_type';
  end if;

  if v_command.module = 'sales' then
    select aggregate into v_aggregate
    from public.erp_sales_workflows
    where organization_id = v_command.organization_id
      and workflow_id = v_command.workflow_id
    for update;
  else
    select aggregate into v_aggregate
    from public.erp_purchase_workflows
    where organization_id = v_command.organization_id
      and workflow_id = v_command.workflow_id
    for update;
  end if;
  if v_aggregate is null then raise exception 'cloud_workflow_not_found'; end if;
  v_cloud_invoice_id := v_aggregate #>> '{invoice,id}';
  v_cloud_currency := v_aggregate #>> '{invoice,currency}';
  v_cloud_remaining := nullif(v_aggregate #>> '{invoice,remainingAmount}', '')::numeric;
  if v_cloud_invoice_id is distinct from p_invoice_id then
    raise exception 'invoice_identity_mismatch';
  end if;
  if v_cloud_currency is distinct from p_invoice_currency then
    raise exception 'invoice_currency_mismatch';
  end if;
  if v_cloud_remaining is null or abs(v_cloud_remaining - p_previous_remaining) > 0.01 then
    raise exception 'stale_invoice_remaining';
  end if;

  select * into v_existing
  from public.erp_payment_settlement_plans
  where command_id = p_command_id;
  if found then
    return jsonb_build_object(
      'planId', v_existing.id,
      'appliedInvoiceAmount', v_existing.applied_invoice_amount,
      'expectedCashAmount', v_existing.expected_cash_amount,
      'actualInvoiceEquivalent', v_existing.actual_invoice_equivalent,
      'exchangeDifference', v_existing.exchange_difference,
      'nextRemaining', v_existing.next_remaining,
      'paymentStatus', v_existing.next_payment_status,
      'journalPlan', v_existing.journal_plan,
      'duplicate', true
    );
  end if;

  if p_invoice_currency not in ('USD','IQD') or p_payment_currency not in ('USD','IQD') then
    raise exception 'unsupported_currency';
  end if;
  if p_previous_remaining <= 0 or p_cash_amount <= 0 or p_exchange_rate <= 0 then
    raise exception 'invalid_payment_amount';
  end if;
  if p_settlement_mode not in ('partial','full_fx') then
    raise exception 'invalid_settlement_mode';
  end if;

  v_applied := case when p_settlement_mode = 'full_fx'
    then p_previous_remaining else p_requested_invoice_amount end;
  if v_applied <= 0 or v_applied > p_previous_remaining + 0.01 then
    raise exception 'invoice_amount_exceeds_remaining';
  end if;

  v_expected := case
    when p_invoice_currency = p_payment_currency then v_applied
    when p_invoice_currency = 'USD' and p_payment_currency = 'IQD' then v_applied * p_exchange_rate
    else v_applied / p_exchange_rate
  end;
  v_actual := case
    when p_invoice_currency = p_payment_currency then p_cash_amount
    when p_invoice_currency = 'USD' and p_payment_currency = 'IQD' then p_cash_amount / p_exchange_rate
    else p_cash_amount * p_exchange_rate
  end;
  v_difference := case when p_settlement_mode = 'full_fx'
    then v_actual - v_applied else 0 end;

  if p_settlement_mode = 'partial' then
    v_tolerance := greatest(0.01, least(1000.0, abs(v_expected) * 0.005));
    if abs(p_cash_amount - v_expected) > v_tolerance then
      raise exception 'cash_amount_mismatch: expected % %', round(v_expected, 2), p_payment_currency;
    end if;
  end if;

  v_next := greatest(0, p_previous_remaining - v_applied);
  v_status := case when v_next <= 0.01 then 'paid' else 'partial' end;

  v_plan := case
    when v_command.module = 'sales' then jsonb_build_array(
      jsonb_build_object('role','cash','accountId',p_cash_account_id,'debit',v_actual,'credit',0),
      case when v_difference < -0.01 then jsonb_build_object('role','fx_loss','accountCode','7190-'||p_invoice_currency,'debit',-v_difference,'credit',0) else null end,
      jsonb_build_object('role','receivable','debit',0,'credit',v_applied),
      case when v_difference > 0.01 then jsonb_build_object('role','fx_gain','accountCode','4190-'||p_invoice_currency,'debit',0,'credit',v_difference) else null end
    )
    else jsonb_build_array(
      jsonb_build_object('role','payable','debit',v_applied,'credit',0),
      case when v_difference > 0.01 then jsonb_build_object('role','fx_loss','accountCode','7190-'||p_invoice_currency,'debit',v_difference,'credit',0) else null end,
      jsonb_build_object('role','cash','accountId',p_cash_account_id,'debit',0,'credit',v_actual),
      case when v_difference < -0.01 then jsonb_build_object('role','fx_gain','accountCode','4190-'||p_invoice_currency,'debit',0,'credit',-v_difference) else null end
    )
  end;
  v_plan := (select coalesce(jsonb_agg(value), '[]'::jsonb) from jsonb_array_elements(v_plan) where value <> 'null'::jsonb);

  insert into public.erp_payment_settlement_plans(
    organization_id, command_id, module, workflow_id, invoice_id,
    invoice_currency, payment_currency, settlement_mode,
    previous_remaining, applied_invoice_amount, cash_amount, exchange_rate,
    expected_cash_amount, actual_invoice_equivalent, exchange_difference,
    next_remaining, next_payment_status, journal_plan, created_by
  ) values (
    v_command.organization_id, p_command_id, v_command.module, v_command.workflow_id, p_invoice_id,
    p_invoice_currency, p_payment_currency, p_settlement_mode,
    p_previous_remaining, v_applied, p_cash_amount, p_exchange_rate,
    v_expected, v_actual, v_difference, v_next, v_status, v_plan, auth.uid()
  ) returning id into v_existing.id;

  update public.erp_financial_commands
  set request_payload = coalesce(request_payload, '{}'::jsonb) || jsonb_build_object(
    'settlementPlanId', v_existing.id,
    'appliedInvoiceAmount', v_applied,
    'exchangeDifference', v_difference,
    'nextRemaining', v_next
  )
  where id = p_command_id;

  return jsonb_build_object(
    'planId', v_existing.id,
    'appliedInvoiceAmount', v_applied,
    'expectedCashAmount', v_expected,
    'actualInvoiceEquivalent', v_actual,
    'exchangeDifference', v_difference,
    'nextRemaining', v_next,
    'paymentStatus', v_status,
    'journalPlan', v_plan,
    'duplicate', false
  );
end;
$$;

grant execute on function public.erp_prepare_payment_settlement(
  uuid,text,text,text,numeric,numeric,numeric,numeric,text,text
) to authenticated;

-- Realtime is useful for payment status displays and audit screens.
do $$ begin
  alter publication supabase_realtime add table public.erp_payment_settlement_plans;
exception when duplicate_object then null; end $$;
