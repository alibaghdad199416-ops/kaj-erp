-- V7.2.1 forward-only repair for linked Supabase lint.
--
-- The V7.2 recycle purge used a session temporary table. The function is
-- valid at runtime, but plpgsql_check cannot resolve a pg_temp relation that
-- is created inside the same function body. Replace the temporary relation
-- with an in-memory UUID queue while preserving exact archive/batch purge,
-- foreign-key retry ordering, permission checks, and source-row cleanup.

create or replace function public.erp_recycle_bin_purge_by_archive(
  p_company_id uuid,
  p_archive_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_archive public.erp_universal_recycle_bin%rowtype;
  v_batch uuid;
  v_queue uuid[]:=array[]::uuid[];
  v_next_queue uuid[]:=array[]::uuid[];
  v_queue_archive_id uuid;
  v_source_table text;
  v_record_id text;
  v_pk text;
  v_has_company_id boolean;
  v_has_company_camel boolean;
  v_actual integer:=0;
  v_deleted integer:=0;
  v_archives integer:=0;
  v_progress integer:=0;
  v_remaining integer:=0;
begin
  if not public.is_company_member(p_company_id) then
    raise exception 'access_denied';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'settings.recycle_bin.purge') then
    raise exception 'permanent_delete_permission_required';
  end if;

  select u.* into v_archive
  from public.erp_universal_recycle_bin u
  where u.id=p_archive_id
    and (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null
    and u.purged_at is null
  for update;

  if not found then
    raise exception 'deleted_record_not_found';
  end if;

  v_batch:=v_archive.deletion_batch_id;
  perform set_config('qualityline.recycle_purge','on',true);

  select coalesce(array_agg(q.archive_id order by q.priority,q.archive_id),array[]::uuid[])
  into v_queue
  from (
    select
      u.id as archive_id,
      case
        when u.source_table in ('erp_journal_lines','erp_inventory_fifo_consumptions') then 10
        when u.source_table in (
          'erp_maintenance_payments','erp_maintenance_parts',
          'erp_sales_order_items_cloud','erp_purchase_order_items_cloud',
          'erp_warehouse_transfer_items','erp_asset_depreciation_entries'
        ) then 20
        when u.source_table in (
          'erp_inventory_movements','erp_inventory_movements_cloud',
          'erp_inventory_cost_layers','erp_cash_transactions'
        ) then 30
        when u.source_table in (
          'erp_commercial_workflow_documents','erp_journal_entries','erp_cloud_journals'
        ) then 40
        when u.source_table in (
          'erp_sales_orders_cloud','erp_purchase_orders_cloud','erp_maintenance_orders',
          'erp_warehouse_transfers','erp_fixed_assets'
        ) then 60
        else 50
      end as priority
    from public.erp_universal_recycle_bin u
    where (u.company_id=p_company_id or u.company_id is null)
      and u.restored_at is null
      and u.purged_at is null
      and (
        u.id=v_archive.id
        or (v_batch is not null and u.deletion_batch_id=v_batch)
      )
  ) q;

  loop
    v_progress:=0;
    v_next_queue:=array[]::uuid[];

    foreach v_queue_archive_id in array v_queue
    loop
      select u.source_table,u.record_id
      into v_source_table,v_record_id
      from public.erp_universal_recycle_bin u
      where u.id=v_queue_archive_id
        and (u.company_id=p_company_id or u.company_id is null)
        and u.restored_at is null
        and u.purged_at is null;

      if not found then
        v_progress:=v_progress+1;
        continue;
      end if;

      begin
        v_deleted:=0;

        if to_regclass(format('public.%I',v_source_table)) is not null then
          select case
            when exists(
              select 1 from information_schema.columns
              where table_schema='public'
                and table_name=v_source_table
                and column_name='id'
            ) then 'id'
            when exists(
              select 1 from information_schema.columns
              where table_schema='public'
                and table_name=v_source_table
                and column_name='record_id'
            ) then 'record_id'
            else null
          end
          into v_pk;

          if v_pk is not null then
            select exists(
              select 1 from information_schema.columns
              where table_schema='public'
                and table_name=v_source_table
                and column_name='company_id'
            ) into v_has_company_id;

            select exists(
              select 1 from information_schema.columns
              where table_schema='public'
                and table_name=v_source_table
                and column_name='companyId'
            ) into v_has_company_camel;

            if v_has_company_id then
              execute format(
                'delete from public.%I where %I::text=$1 and company_id::text=$2',
                v_source_table,v_pk
              ) using v_record_id,p_company_id::text;
            elsif v_has_company_camel then
              execute format(
                'delete from public.%I where %I::text=$1 and "companyId"::text=$2',
                v_source_table,v_pk
              ) using v_record_id,p_company_id::text;
            else
              execute format(
                'delete from public.%I where %I::text=$1',
                v_source_table,v_pk
              ) using v_record_id;
            end if;

            get diagnostics v_deleted=row_count;
            v_actual:=v_actual+v_deleted;
          end if;
        end if;

        v_progress:=v_progress+1;
      exception
        when foreign_key_violation then
          v_next_queue:=array_append(v_next_queue,v_queue_archive_id);
      end;
    end loop;

    v_remaining:=coalesce(cardinality(v_next_queue),0);
    exit when v_remaining=0;

    if v_progress=0 then
      raise exception 'permanent_delete_blocked_by_active_relationships';
    end if;

    v_queue:=v_next_queue;
  end loop;

  delete from public.erp_universal_recycle_bin u
  where (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null
    and u.purged_at is null
    and (
      u.id=v_archive.id
      or (v_batch is not null and u.deletion_batch_id=v_batch)
    );
  get diagnostics v_archives=row_count;

  return jsonb_build_object(
    'purged',v_archives>0,
    'archiveId',p_archive_id,
    'deletionBatchId',v_batch,
    'archiveRowsRemoved',v_archives,
    'sourceRowsProcessed',v_actual,
    'batchPurged',v_batch is not null
  );
end;
$$;

revoke all on function public.erp_recycle_bin_purge_by_archive(uuid,uuid) from public,anon;
grant execute on function public.erp_recycle_bin_purge_by_archive(uuid,uuid) to authenticated,service_role;
