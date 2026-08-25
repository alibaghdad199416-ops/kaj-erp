-- V7.1.1 forward-only repair for the linked database lint result.
--
-- V7.1 soft-deletes normalized sales and purchase order lines and records a
-- deletion timestamp. The normalized item tables historically had is_deleted
-- and updated_at, but did not have deleted_at. Add the missing audit column
-- instead of changing the already-applied V7.1 migration or weakening the
-- linked-delete workflow.

alter table public.erp_sales_order_items_cloud
  add column if not exists deleted_at timestamptz;

alter table public.erp_purchase_order_items_cloud
  add column if not exists deleted_at timestamptz;

update public.erp_sales_order_items_cloud
set deleted_at=coalesce(deleted_at,updated_at,now())
where is_deleted and deleted_at is null;

update public.erp_purchase_order_items_cloud
set deleted_at=coalesce(deleted_at,updated_at,now())
where is_deleted and deleted_at is null;

create index if not exists erp_sales_order_items_cloud_deleted_order_idx
  on public.erp_sales_order_items_cloud(company_id,order_id,deleted_at)
  where is_deleted;

create index if not exists erp_purchase_order_items_cloud_deleted_order_idx
  on public.erp_purchase_order_items_cloud(company_id,order_id,deleted_at)
  where is_deleted;

comment on column public.erp_sales_order_items_cloud.deleted_at is
  'Soft-deletion timestamp used by linked sales deletion and recycle auditing.';

comment on column public.erp_purchase_order_items_cloud.deleted_at is
  'Soft-deletion timestamp used by linked purchase deletion and recycle auditing.';