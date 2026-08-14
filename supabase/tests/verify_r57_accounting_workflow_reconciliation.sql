\set ON_ERROR_STOP on
\pset pager off

begin;

do $$
declare definition text;
begin
  if public.erp_r57_canonical_account_code('1000.009999999') <> '100001'
     or public.erp_r57_canonical_account_code('5000.020000000') <> '500002'
     or public.erp_r57_canonical_account_code('1000.00') <> '1000' then
    raise exception 'R57 account identifier canonicalization failed';
  end if;
  if to_regprocedure('public.erp_r57_accounting_header_snapshot(uuid)') is null
     or to_regprocedure('public.erp_r57_commercial_reconciliation(uuid,uuid,text)') is null then
    raise exception 'R57 bounded read RPCs are missing';
  end if;
  select pg_get_functiondef('public.erp_r57_guard_commercial_document_quantities()'::regprocedure) into definition;
  if definition not like '%r57_quantity_exceeds_order%'
     or definition not like '%r57_invoice_exceeds_approved_operational%'
     or definition like '%least(%' then
    raise exception 'R57 hard quantity boundaries are incomplete or silently clamp';
  end if;
  if not exists(select 1 from pg_trigger where tgname='erp_r57_commercial_quantity_guard' and not tgisinternal)
     or not exists(select 1 from pg_trigger where tgname='erp_r57_commercial_discrepancy_refresh' and not tgisinternal) then
    raise exception 'R57 workflow triggers are missing';
  end if;
  if has_function_privilege('anon','public.erp_r57_accounting_header_snapshot(uuid)','execute')
     or has_function_privilege('anon','public.erp_r57_commercial_reconciliation(uuid,uuid,text)','execute') then
    raise exception 'R57 tenant reads exposed to anon';
  end if;
end $$;

rollback;
\echo 'R57 accounting and workflow reconciliation PASS'
