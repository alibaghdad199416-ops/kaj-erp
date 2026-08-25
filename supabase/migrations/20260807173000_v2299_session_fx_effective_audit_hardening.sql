-- Quality Line ERP V22.9.9
-- Runtime hardening requested after V22.9.8 R2:
-- * preserve high precision FX values (15 decimal places, matching Dart/Web numeric safety)
-- * keep historical/future operational timestamps as the accounting/inventory effective timestamp
-- This migration intentionally does not alter Supabase project/auth configuration.

do $$
declare
  r record;
begin
  for r in
    select table_schema, table_name, column_name
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'exchange_rate'
      and table_name in (
        'erp_sales_orders_cloud',
        'erp_purchase_orders_cloud',
        'erp_maintenance_orders_cloud',
        'erp_maintenance_payments_cloud',
        'erp_payment_settlements',
        'erp_company_currencies'
      )
  loop
    execute format(
      'alter table %I.%I alter column %I type numeric(38,15) using %I::numeric(38,15)',
      r.table_schema, r.table_name, r.column_name, r.column_name
    );
  end loop;
end $$;

-- Existing effective_at infrastructure is authoritative. Backfill only nulls;
-- never replace a user-selected historical or future timestamp.
update public.erp_sales_orders_cloud
set effective_at = coalesce(effective_at, created_at, now())
where effective_at is null;

update public.erp_purchase_orders_cloud
set effective_at = coalesce(effective_at, created_at, now())
where effective_at is null;

update public.erp_commercial_workflow_documents
set effective_at = coalesce(effective_at, created_at, now())
where effective_at is null;

comment on column public.erp_sales_orders_cloud.effective_at is
  'User-selected operational timestamp; drives numbering, stock and accounting effective period.';
comment on column public.erp_purchase_orders_cloud.effective_at is
  'User-selected operational timestamp; drives numbering, stock and accounting effective period.';
comment on column public.erp_commercial_workflow_documents.effective_at is
  'Inherited/user-selected operational timestamp used by workflow posting and reversals.';
