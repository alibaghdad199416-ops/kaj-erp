-- Quality Line ERP v17.15.5: durable tombstones for normalized master data.
begin;

do $$
declare
  t text;
begin
  foreach t in array array['erp_cars','erp_customers','erp_suppliers'] loop
    execute format('alter table public.%I add column if not exists is_deleted boolean not null default false', t);
    execute format('alter table public.%I add column if not exists deleted_at timestamptz', t);
    execute format('create index if not exists %I on public.%I(company_id, is_deleted, updated_at desc)', t || '_active_sync_idx', t);
  end loop;
end $$;

commit;
