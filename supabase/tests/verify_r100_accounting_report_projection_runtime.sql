\set ON_ERROR_STOP on
\pset pager off

begin;

do $$
declare
  v_report text;
  v_key text;
  v_expected text;
begin
  -- The public mapper must expose every Trial Balance split amount and the GL
  -- running-balance/hierarchy keys through existing accounting field grants.
  for v_key,v_expected in
    select * from (values
      ('openingDebit','debit'),
      ('openingCredit','credit'),
      ('periodDebit','debit'),
      ('periodCredit','credit'),
      ('closingDebit','debit'),
      ('closingCredit','credit'),
      ('runningBalance','balances'),
      ('parentAccountId','parentAccount'),
      ('rootAccountCode','accountCode'),
      ('rootAccountName','accountName'),
      ('hierarchyPath','accountName'),
      ('hierarchyDepth','parentAccount'),
      ('partyName','reference')
    ) as x(k,v)
  loop
    if public.erp_r9_result_field_for_key('accounting',v_key) is distinct from v_expected then
      raise exception 'r100_accounting_projection_mapping_incorrect:%:%',
        v_key,public.erp_r9_result_field_for_key('accounting',v_key);
    end if;
  end loop;

  -- The established calculations remain authoritative: Trial Balance computes
  -- opening/period/closing debit-credit splits and General Ledger computes a
  -- natural running balance from the opening amount plus ordered journal deltas.
  select pg_get_functiondef(
    'public.erp_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz)'::regprocedure
  ) into v_report;
  if v_report not like '%''openingDebit''%'
     or v_report not like '%''openingCredit''%'
     or v_report not like '%''periodDebit''%'
     or v_report not like '%''periodCredit''%'
     or v_report not like '%''closingDebit''%'
     or v_report not like '%''closingCredit''%'
     or v_report not like '%opening_signed+period_debit-period_credit%'
     or v_report not like '%sum(line.natural_delta) over%'
     or v_report not like '%''runningBalance''%' then
    raise exception 'r100_accounting_report_calculation_contract_missing';
  end if;
end $$;

-- Exercise the same R9 field filter used by the browser. Replace only the
-- permission predicates inside this transaction so the test can force
-- restricted mode without constructing a role catalog fixture.
create or replace function public.erp_cloud_user_has_permission(
  p_company_id uuid,p_permission_code text
) returns boolean
language sql stable security definer set search_path=public as $$
  select trim(coalesce(p_permission_code,''))='accounting.fields.restrict'
$$;

create or replace function public.erp_cloud_user_can_view_field(
  p_company_id uuid,p_resource text,p_field text,p_base_permission text default null
) returns boolean
language sql stable security definer set search_path=public as $$
  select trim(coalesce(p_resource,''))='accounting'
     and trim(coalesce(p_field,'')) in (
       'accountCode','accountName','accountType','parentAccount','currency',
       'openingBalance','entryNumber','entryDate','description','journalLines',
       'debit','credit','reference','balances'
     )
$$;

do $$
declare
  v_payload jsonb:=jsonb_build_object(
    'accountId','r100-account',
    'accountCode','1100',
    'accountName','R100 Cash',
    'accountType','asset',
    'parentAccountId','1000',
    'rootAccountCode','1000',
    'rootAccountName','Assets',
    'hierarchyPath','Assets / R100 Cash',
    'hierarchyDepth',1,
    'currency','USD',
    'openingDebit',10,
    'openingCredit',0,
    'periodDebit',25,
    'periodCredit',5,
    'closingDebit',30,
    'closingCredit',0,
    'entryNumber','JE-R100',
    'entryDate','2026-08-21T10:00:00Z',
    'description','R100 projection test',
    'partyName','Counterparty',
    'referenceType','test',
    'referenceId','r100-ref',
    'openingBalance',10,
    'debit',25,
    'credit',5,
    'runningBalance',30,
    'shouldDisappear','unknown-field'
  );
  v_filtered jsonb;
begin
  v_filtered:=public.erp_r9_filter_result_json(
    '00000000-0000-0000-0000-000000000001',
    'accounting',v_payload,null
  );

  if not (v_filtered ?& array[
      'accountId','accountCode','accountName','accountType','parentAccountId',
      'rootAccountCode','rootAccountName','hierarchyPath','hierarchyDepth',
      'currency','openingDebit','openingCredit','periodDebit','periodCredit',
      'closingDebit','closingCredit','entryNumber','entryDate','description',
      'partyName','referenceType','referenceId','openingBalance','debit','credit',
      'runningBalance'
    ]) then
    raise exception 'r100_restricted_accounting_projection_dropped_required_fields:%',v_filtered;
  end if;
  if v_filtered ? 'shouldDisappear' then
    raise exception 'r100_unknown_accounting_field_not_default_denied';
  end if;
end $$;

rollback;
select 'R100 Trial Balance + GL projection runtime PASS' as result;
