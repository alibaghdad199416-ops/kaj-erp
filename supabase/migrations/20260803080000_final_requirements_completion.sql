begin;

-- Final requirements completion:
-- * every accounting delete uses the dedicated accounting.delete permission;
-- * legacy/partially-linked expense and cash documents can be cleaned safely;
-- * deleting a generated journal routes to its owning business document.

create or replace function public.erp_delete_cloud_expense(
  p_company_id uuid,
  p_expense_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_expense public.erp_expenses%rowtype;
  v_journal_id text;
  v_cash_transaction_id text;
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,
    array['accounting.delete']
  );

  select * into v_expense
    from public.erp_expenses
   where company_id=p_company_id
     and id=p_expense_id
     and not is_deleted
   for update;
  if not found then return; end if;

  v_journal_id:=nullif(v_expense.data->>'journalEntryId','');
  v_cash_transaction_id:=nullif(v_expense.data->>'cashTransactionId','');

  -- Remove every cash movement linked to the expense, including historical
  -- rows whose direct id was not copied back to the expense document.
  update public.erp_cash_transactions
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and not is_deleted
     and (
       id=v_cash_transaction_id
       or (
         lower(coalesce(data->>'referenceType',''))='expense'
         and data->>'referenceId'=p_expense_id
       )
     );

  -- Delete both the explicit journal and any historical journal that points
  -- directly to the expense id.
  update public.erp_journal_lines
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and not is_deleted
     and (
       data->>'entryId'=v_journal_id
       or data->>'entryId' in (
         select id
           from public.erp_journal_entries
          where company_id=p_company_id
            and not is_deleted
            and lower(coalesce(data->>'referenceType',''))='expense'
            and data->>'referenceId'=p_expense_id
       )
     );

  update public.erp_journal_entries
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and not is_deleted
     and (
       id=v_journal_id
       or (
         lower(coalesce(data->>'referenceType',''))='expense'
         and data->>'referenceId'=p_expense_id
       )
     );

  update public.erp_expenses
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and id=p_expense_id
     and not is_deleted;
end;
$$;

create or replace function public.erp_delete_cloud_cash_transaction(
  p_company_id uuid,
  p_transaction_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transaction public.erp_cash_transactions%rowtype;
  v_journal_id text;
  v_reference_type text;
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,
    array['accounting.delete']
  );

  select * into v_transaction
    from public.erp_cash_transactions
   where company_id=p_company_id
     and id=p_transaction_id
     and not is_deleted
   for update;
  if not found then return; end if;

  v_journal_id:=nullif(v_transaction.data->>'journalEntryId','');
  v_reference_type:=lower(trim(coalesce(
    nullif(v_transaction.data->>'referenceType',''),
    'manual_cash_transaction'
  )));

  if v_reference_type not in ('manual_cash_transaction','cash_transaction') then
    raise exception 'لا يمكن حذف حركة مرتبطة مباشرة؛ احذف المستند الأصلي';
  end if;

  update public.erp_cash_transactions
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and id=p_transaction_id
     and not is_deleted;

  if v_journal_id is not null then
    update public.erp_journal_lines
       set is_deleted=true,
           deleted_at=v_now,
           updated_at=v_now,
           updated_by=auth.uid()
     where company_id=p_company_id
       and data->>'entryId'=v_journal_id
       and not is_deleted;

    update public.erp_journal_entries
       set is_deleted=true,
           deleted_at=v_now,
           updated_at=v_now,
           updated_by=auth.uid()
     where company_id=p_company_id
       and id=v_journal_id
       and not is_deleted;
  end if;
end;
$$;

create or replace function public.erp_delete_cloud_cash_transfer(
  p_company_id uuid,
  p_transfer_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz:=now();
  v_transaction record;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,
    array['accounting.delete']
  );

  perform 1
    from public.erp_cash_transfers
   where company_id=p_company_id
     and id=p_transfer_id
     and not is_deleted
   for update;
  if not found then return; end if;

  -- Repair-friendly cleanup: older interrupted transfers may contain only one
  -- side or a missing journal. Delete every linked row that exists instead of
  -- blocking the user behind an unrecoverable integrity error.
  for v_transaction in
    select id,nullif(data->>'journalEntryId','') as journal_id
      from public.erp_cash_transactions
     where company_id=p_company_id
       and not is_deleted
       and lower(coalesce(data->>'referenceType',''))='cash_transfer'
       and data->>'referenceId'=p_transfer_id
     for update
  loop
    if v_transaction.journal_id is not null then
      update public.erp_journal_lines
         set is_deleted=true,
             deleted_at=v_now,
             updated_at=v_now,
             updated_by=auth.uid()
       where company_id=p_company_id
         and not is_deleted
         and data->>'entryId'=v_transaction.journal_id;

      update public.erp_journal_entries
         set is_deleted=true,
             deleted_at=v_now,
             updated_at=v_now,
             updated_by=auth.uid()
       where company_id=p_company_id
         and id=v_transaction.journal_id
         and not is_deleted;
    end if;

    update public.erp_cash_transactions
       set is_deleted=true,
           deleted_at=v_now,
           updated_at=v_now,
           updated_by=auth.uid()
     where company_id=p_company_id
       and id=v_transaction.id
       and not is_deleted;
  end loop;

  -- Also remove orphaned transfer journals that no longer have a cash-row link.
  update public.erp_journal_lines
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and not is_deleted
     and data->>'entryId' in (
       select id
         from public.erp_journal_entries
        where company_id=p_company_id
          and not is_deleted
          and lower(coalesce(data->>'referenceType',''))='cash_transfer'
          and data->>'referenceId'=p_transfer_id
     );

  update public.erp_journal_entries
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and not is_deleted
     and lower(coalesce(data->>'referenceType',''))='cash_transfer'
     and data->>'referenceId'=p_transfer_id;

  update public.erp_cash_transfers
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and id=p_transfer_id
     and not is_deleted;
end;
$$;

create or replace function public.erp_delete_cloud_accounting_entry(
  p_company_id uuid,
  p_entry_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_entry public.erp_journal_entries%rowtype;
  v_ref text;
  v_reference_id text;
  v_order_id text;
  v_reference_uuid uuid;
  v_order_uuid uuid;
  v_doc record;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,
    array['accounting.delete']
  );

  select * into v_entry
    from public.erp_journal_entries
   where company_id=p_company_id
     and id=p_entry_id
     and not is_deleted
   for update;
  if not found then return; end if;

  v_ref:=lower(coalesce(
    nullif(v_entry.data->>'referenceType',''),
    nullif(v_entry.data->>'reference_type',''),
    'manual'
  ));
  v_reference_id:=coalesce(
    nullif(v_entry.data->>'referenceId',''),
    nullif(v_entry.data->>'reference_id',''),
    nullif(v_entry.data->>'maintenanceOrderId',''),
    nullif(v_entry.data->>'cashTransactionId','')
  );
  v_order_id:=coalesce(
    nullif(v_entry.data->>'orderId',''),
    nullif(v_entry.data->>'order_id','')
  );

  if v_ref in ('manual','manual_journal') then
    perform public.erp_delete_cloud_manual_journal(p_company_id,p_entry_id);
    return;
  end if;

  -- Accounting documents with text ids must be routed before UUID parsing.
  if v_ref='expense' and v_reference_id is not null then
    perform public.erp_delete_cloud_expense(p_company_id,v_reference_id);
    return;
  end if;

  if v_ref in ('manual_cash_transaction','cash_transaction')
     and v_reference_id is not null then
    perform public.erp_delete_cloud_cash_transaction(
      p_company_id,
      v_reference_id
    );
    return;
  end if;

  if v_ref='cash_transfer' and v_reference_id is not null then
    perform public.erp_delete_cloud_cash_transfer(p_company_id,v_reference_id);
    return;
  end if;

  begin
    v_reference_uuid:=v_reference_id::uuid;
  exception when invalid_text_representation then
    v_reference_uuid:=null;
  end;
  begin
    v_order_uuid:=v_order_id::uuid;
  exception when invalid_text_representation then
    v_order_uuid:=null;
  end;

  if v_reference_uuid is not null
     and (
       v_ref like 'maintenance%'
       or exists(
         select 1
           from public.erp_maintenance_orders
          where company_id=p_company_id
            and id=v_reference_uuid
            and not is_deleted
       )
     ) then
    perform public.erp_delete_cloud_maintenance_order(
      p_company_id,
      v_reference_uuid,
      'حذف من القيد المحاسبي المرتبط'
    );
    return;
  end if;

  if v_reference_uuid is not null then
    select module,parent_id into v_doc
      from public.erp_commercial_workflow_documents
     where company_id=p_company_id
       and id=v_reference_uuid
       and not is_deleted
     limit 1;
    if found and v_doc.module='sales' then
      perform public.erp_delete_cloud_sales_order(p_company_id,v_doc.parent_id);
      return;
    elsif found and v_doc.module='purchases' then
      perform public.erp_delete_cloud_purchase_order(p_company_id,v_doc.parent_id);
      return;
    end if;
  end if;

  if v_order_uuid is not null and exists(
    select 1
      from public.erp_sales_orders_cloud
     where company_id=p_company_id
       and id=v_order_uuid
       and not is_deleted
  ) then
    perform public.erp_delete_cloud_sales_order(p_company_id,v_order_uuid);
    return;
  end if;

  if v_order_uuid is not null and exists(
    select 1
      from public.erp_purchase_orders_cloud
     where company_id=p_company_id
       and id=v_order_uuid
       and not is_deleted
  ) then
    perform public.erp_delete_cloud_purchase_order(p_company_id,v_order_uuid);
    return;
  end if;

  if v_reference_uuid is not null and exists(
    select 1
      from public.erp_sales_orders_cloud
     where company_id=p_company_id
       and id=v_reference_uuid
       and not is_deleted
  ) then
    perform public.erp_delete_cloud_sales_order(p_company_id,v_reference_uuid);
    return;
  end if;

  if v_reference_uuid is not null and exists(
    select 1
      from public.erp_purchase_orders_cloud
     where company_id=p_company_id
       and id=v_reference_uuid
       and not is_deleted
  ) then
    perform public.erp_delete_cloud_purchase_order(p_company_id,v_reference_uuid);
    return;
  end if;

  if v_reference_id is not null and exists(
    select 1
      from public.erp_sales
     where company_id=p_company_id
       and id=v_reference_id
       and not is_deleted
  ) then
    perform public.erp_delete_cloud_sale(p_company_id,v_reference_id);
    return;
  end if;

  if v_reference_id is not null and exists(
    select 1
      from public.erp_purchases
     where company_id=p_company_id
       and id=v_reference_id
       and not is_deleted
  ) then
    perform public.erp_delete_cloud_purchase(p_company_id,v_reference_id);
    return;
  end if;

  raise exception 'لا يمكن حذف القيد المولد منفرداً؛ احذف المستند المصدر أو امنح صلاحية حذف المستند المرتبط';
end;
$$;

revoke all on function public.erp_delete_cloud_expense(uuid,text) from public,anon;
revoke all on function public.erp_delete_cloud_cash_transaction(uuid,text) from public,anon;
revoke all on function public.erp_delete_cloud_cash_transfer(uuid,text) from public,anon;
revoke all on function public.erp_delete_cloud_accounting_entry(uuid,text) from public,anon;

grant execute on function public.erp_delete_cloud_expense(uuid,text) to authenticated;
grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text) to authenticated;
grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text) to authenticated;
grant execute on function public.erp_delete_cloud_accounting_entry(uuid,text) to authenticated;

commit;
