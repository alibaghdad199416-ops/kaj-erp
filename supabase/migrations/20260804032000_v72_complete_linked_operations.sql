-- V7.2 complete linked operations repair.
--
-- Goals:
-- * product warehouse transfers are one visible source-to-destination document;
-- * transfer deletion reverses stock and verifies every audit link is retired;
-- * sales, purchase, and maintenance deletion is atomic while partner payments
--   remain as editable/deletable unapplied balances;
-- * recycle-bin permanent deletion targets an exact archive/batch;
-- * partner subledgers include preserved payments;
-- * product and vehicle accounting assignments remain normalized.

alter table public.erp_sales_order_items_cloud
  add column if not exists deleted_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

alter table public.erp_purchase_order_items_cloud
  add column if not exists deleted_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

-- Keep both normalized and compatibility aliases for existing vehicle records.
update public.erp_cars as c
set data=c.data||jsonb_build_object(
      'inventory_asset_account_id',coalesce(c.data->>'inventory_asset_account_id',c.data->>'inventoryAssetAccountId'),
      'inventoryAssetAccountId',coalesce(c.data->>'inventoryAssetAccountId',c.data->>'inventory_asset_account_id'),
      'sales_cost_expense_account_id',coalesce(c.data->>'sales_cost_expense_account_id',c.data->>'salesCostExpenseAccountId'),
      'salesCostExpenseAccountId',coalesce(c.data->>'salesCostExpenseAccountId',c.data->>'sales_cost_expense_account_id'),
      'updatedAt',now()
    ),
    updated_at=now()
where not c.is_deleted
  and (
    coalesce(c.data->>'inventory_asset_account_id','')<>coalesce(c.data->>'inventoryAssetAccountId','')
    or coalesce(c.data->>'sales_cost_expense_account_id','')<>coalesce(c.data->>'salesCostExpenseAccountId','')
  );

create or replace function public.erp_delete_inventory_warehouse_transfer_v2(
  p_company_id uuid,
  p_transfer_id text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_active_header integer;
  v_active_items integer;
  v_active_movements integer;
begin
  perform public.erp_delete_inventory_warehouse_transfer(
    p_company_id,p_transfer_id,p_reason
  );

  select count(*) into v_active_header
  from public.erp_warehouse_transfers as t
  where t.company_id=p_company_id and t.id=p_transfer_id and not t.is_deleted;

  select count(*) into v_active_items
  from public.erp_warehouse_transfer_items as i
  where i.company_id=p_company_id and not i.is_deleted
    and coalesce(i.data->>'transferId',i.data->>'transfer_id')=p_transfer_id;

  select count(*) into v_active_movements
  from public.erp_inventory_movements as m
  where m.company_id=p_company_id and not m.is_deleted
    and lower(coalesce(m.data->>'referenceType',m.data->>'reference_type',''))='warehouse_transfer'
    and coalesce(m.data->>'referenceId',m.data->>'reference_id')=p_transfer_id;

  if v_active_header+v_active_items+v_active_movements<>0 then
    raise exception 'warehouse_transfer_link_cleanup_incomplete';
  end if;

  return jsonb_build_object(
    'deleted',true,
    'transferId',p_transfer_id,
    'singleDocument',true,
    'stockReversed',true,
    'activeHeaders',v_active_header,
    'activeItems',v_active_items,
    'activeMovements',v_active_movements
  );
end;
$$;

-- Finalize commercial deletion after the established V7.1 payment-detach and
-- reversal functions. Residual legacy records are retired in the same SQL
-- transaction; preserved partner advances are explicitly excluded.
create or replace function public.erp_delete_cloud_sales_order_v2(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz:=now();
  v_active integer;
  v_preserved integer;
begin
  perform public.erp_delete_cloud_sales_order(p_company_id,p_order_id);

  update public.erp_sales as s
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=s.data||jsonb_build_object('deletedAt',v_now,'deletedFromOrderId',p_order_id,'paymentDisposition','customer_unapplied_credit')
  where s.company_id=p_company_id and not s.is_deleted
    and coalesce(s.data->>'orderId',s.data->>'order_id',s.data->>'salesOrderId',s.data->>'sales_order_id')=p_order_id::text;

  update public.erp_commercial_workflow_documents as d
  set is_deleted=true,deleted_at=coalesce(d.deleted_at,v_now),updated_at=v_now,updated_by=auth.uid()
  where d.company_id=p_company_id and d.parent_id=p_order_id and d.module='sales' and not d.is_deleted;

  update public.erp_sales_order_items_cloud as i
  set is_deleted=true,deleted_at=coalesce(i.deleted_at,v_now),updated_at=v_now
  where i.company_id=p_company_id and i.order_id=p_order_id and not i.is_deleted;

  update public.erp_sales_orders_cloud as o
  set is_deleted=true,deleted_at=coalesce(o.deleted_at,v_now),updated_at=v_now
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;

  update public.erp_cash_transactions as ct
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=ct.data||jsonb_build_object('deleteReason','Retired residual sales link','deletedAt',v_now)
  where ct.company_id=p_company_id and not ct.is_deleted
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))<>'partner_advance'
    and coalesce(ct.data->>'orderId',ct.data->>'order_id',ct.data->>'salesOrderId',ct.data->>'sales_order_id')=p_order_id::text;

  update public.erp_journal_entries as je
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=je.data||jsonb_build_object('deleteReason','Retired residual sales link','deletedAt',v_now)
  where je.company_id=p_company_id and not je.is_deleted
    and lower(coalesce(je.data->>'referenceType',je.data->>'reference_type',''))<>'partner_advance'
    and coalesce(je.data->>'orderId',je.data->>'order_id',je.data->>'salesOrderId',je.data->>'sales_order_id')=p_order_id::text;

  update public.erp_journal_lines as jl
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where jl.company_id=p_company_id and not jl.is_deleted
    and exists(
      select 1 from public.erp_journal_entries je
      where je.company_id=p_company_id and je.is_deleted
        and je.id=coalesce(jl.data->>'entryId',jl.data->>'entry_id')
        and coalesce(je.data->>'orderId',je.data->>'order_id',je.data->>'salesOrderId',je.data->>'sales_order_id')=p_order_id::text
    );

  select count(*) into v_active from (
    select 1 from public.erp_sales_orders_cloud o where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
    union all select 1 from public.erp_sales_order_items_cloud i where i.company_id=p_company_id and i.order_id=p_order_id and not i.is_deleted
    union all select 1 from public.erp_commercial_workflow_documents d where d.company_id=p_company_id and d.parent_id=p_order_id and d.module='sales' and not d.is_deleted
  ) q;
  if v_active<>0 then raise exception 'sales_link_cleanup_incomplete'; end if;

  select count(*) into v_preserved
  from public.erp_cash_transactions ct
  where ct.company_id=p_company_id and not ct.is_deleted
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
    and coalesce(ct.data->>'detachedFromOrderId',ct.data->>'detached_from_order_id')=p_order_id::text;

  return jsonb_build_object(
    'deleted',true,'module','sales','orderId',p_order_id,
    'paymentsPreserved',true,'preservedPaymentCount',v_preserved,
    'paymentDisposition','customer_unapplied_credit','activeLinks',v_active
  );
end;
$$;

create or replace function public.erp_delete_cloud_purchase_order_v2(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz:=now();
  v_active integer;
  v_preserved integer;
begin
  perform public.erp_delete_cloud_purchase_order(p_company_id,p_order_id);

  update public.erp_purchases as p
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=p.data||jsonb_build_object('deletedAt',v_now,'deletedFromOrderId',p_order_id,'paymentDisposition','supplier_unapplied_debit')
  where p.company_id=p_company_id and not p.is_deleted
    and coalesce(p.data->>'orderId',p.data->>'order_id',p.data->>'purchaseOrderId',p.data->>'purchase_order_id')=p_order_id::text;

  update public.erp_commercial_workflow_documents as d
  set is_deleted=true,deleted_at=coalesce(d.deleted_at,v_now),updated_at=v_now,updated_by=auth.uid()
  where d.company_id=p_company_id and d.parent_id=p_order_id and d.module='purchases' and not d.is_deleted;

  update public.erp_purchase_order_items_cloud as i
  set is_deleted=true,deleted_at=coalesce(i.deleted_at,v_now),updated_at=v_now
  where i.company_id=p_company_id and i.order_id=p_order_id and not i.is_deleted;

  update public.erp_purchase_orders_cloud as o
  set is_deleted=true,deleted_at=coalesce(o.deleted_at,v_now),updated_at=v_now
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;

  update public.erp_cash_transactions as ct
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=ct.data||jsonb_build_object('deleteReason','Retired residual purchase link','deletedAt',v_now)
  where ct.company_id=p_company_id and not ct.is_deleted
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))<>'partner_advance'
    and coalesce(ct.data->>'orderId',ct.data->>'order_id',ct.data->>'purchaseOrderId',ct.data->>'purchase_order_id')=p_order_id::text;

  update public.erp_journal_entries as je
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=je.data||jsonb_build_object('deleteReason','Retired residual purchase link','deletedAt',v_now)
  where je.company_id=p_company_id and not je.is_deleted
    and lower(coalesce(je.data->>'referenceType',je.data->>'reference_type',''))<>'partner_advance'
    and coalesce(je.data->>'orderId',je.data->>'order_id',je.data->>'purchaseOrderId',je.data->>'purchase_order_id')=p_order_id::text;

  update public.erp_journal_lines as jl
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where jl.company_id=p_company_id and not jl.is_deleted
    and exists(
      select 1 from public.erp_journal_entries je
      where je.company_id=p_company_id and je.is_deleted
        and je.id=coalesce(jl.data->>'entryId',jl.data->>'entry_id')
        and coalesce(je.data->>'orderId',je.data->>'order_id',je.data->>'purchaseOrderId',je.data->>'purchase_order_id')=p_order_id::text
    );

  select count(*) into v_active from (
    select 1 from public.erp_purchase_orders_cloud o where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
    union all select 1 from public.erp_purchase_order_items_cloud i where i.company_id=p_company_id and i.order_id=p_order_id and not i.is_deleted
    union all select 1 from public.erp_commercial_workflow_documents d where d.company_id=p_company_id and d.parent_id=p_order_id and d.module='purchases' and not d.is_deleted
  ) q;
  if v_active<>0 then raise exception 'purchase_link_cleanup_incomplete'; end if;

  select count(*) into v_preserved
  from public.erp_cash_transactions ct
  where ct.company_id=p_company_id and not ct.is_deleted
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
    and coalesce(ct.data->>'detachedFromOrderId',ct.data->>'detached_from_order_id')=p_order_id::text;

  return jsonb_build_object(
    'deleted',true,'module','purchases','orderId',p_order_id,
    'paymentsPreserved',true,'preservedPaymentCount',v_preserved,
    'paymentDisposition','supplier_unapplied_debit','activeLinks',v_active
  );
end;
$$;

create or replace function public.erp_delete_cloud_maintenance_order_v2(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz:=now();
  v_active integer;
  v_preserved integer;
begin
  perform public.erp_delete_cloud_maintenance_order(p_company_id,p_order_id,p_reason);

  update public.erp_commercial_workflow_documents as d
  set is_deleted=true,deleted_at=coalesce(d.deleted_at,v_now),updated_at=v_now,updated_by=auth.uid()
  where d.company_id=p_company_id and d.parent_id=p_order_id
    and d.module='maintenance' and not d.is_deleted;

  update public.erp_cash_transactions as ct
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=ct.data||jsonb_build_object('deleteReason','Retired residual maintenance link','deletedAt',v_now)
  where ct.company_id=p_company_id and not ct.is_deleted
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))<>'partner_advance'
    and coalesce(ct.data->>'maintenanceOrderId',ct.data->>'maintenance_order_id',ct.data->>'orderId',ct.data->>'order_id')=p_order_id::text;

  update public.erp_journal_entries as je
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=je.data||jsonb_build_object('deleteReason','Retired residual maintenance link','deletedAt',v_now)
  where je.company_id=p_company_id and not je.is_deleted
    and lower(coalesce(je.data->>'referenceType',je.data->>'reference_type',''))<>'partner_advance'
    and coalesce(je.data->>'maintenanceOrderId',je.data->>'maintenance_order_id',je.data->>'orderId',je.data->>'order_id')=p_order_id::text;

  update public.erp_journal_lines as jl
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where jl.company_id=p_company_id and not jl.is_deleted
    and exists(
      select 1 from public.erp_journal_entries je
      where je.company_id=p_company_id and je.is_deleted
        and je.id=coalesce(jl.data->>'entryId',jl.data->>'entry_id')
        and coalesce(je.data->>'maintenanceOrderId',je.data->>'maintenance_order_id',je.data->>'orderId',je.data->>'order_id')=p_order_id::text
    );

  update public.erp_maintenance_payments as mp
  set is_unapplied=true,
      detached_from_order_id=coalesce(mp.detached_from_order_id,p_order_id),
      partner_type=coalesce(mp.partner_type,'customer'),
      detached_at=coalesce(mp.detached_at,v_now)
  where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
    and not mp.is_deleted;

  select count(*) into v_active from (
    select 1 from public.erp_maintenance_orders o where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
    union all select 1 from public.erp_maintenance_parts p where p.company_id=p_company_id and p.maintenance_order_id=p_order_id and not p.is_deleted
    union all select 1 from public.erp_commercial_workflow_documents d where d.company_id=p_company_id and d.parent_id=p_order_id and d.module='maintenance' and not d.is_deleted
  ) q;
  if v_active<>0 then raise exception 'maintenance_link_cleanup_incomplete'; end if;

  select count(*) into v_preserved
  from public.erp_cash_transactions ct
  where ct.company_id=p_company_id and not ct.is_deleted
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
    and coalesce(ct.data->>'detachedFromMaintenanceOrderId',ct.data->>'detached_from_maintenance_order_id')=p_order_id::text;

  return jsonb_build_object(
    'deleted',true,'module','maintenance','orderId',p_order_id,
    'paymentsPreserved',true,'preservedPaymentCount',v_preserved,
    'paymentDisposition','customer_unapplied_credit','activeLinks',v_active
  );
end;
$$;

-- Preserved partner payments are first-class account movements. They remain
-- editable/deletable independently from the deleted operational document.
create or replace function public.erp_list_partner_unapplied_payments(
  p_company_id uuid,
  p_party_type text,
  p_party_id text,
  p_currency text
) returns setof jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'transaction_id',ct.id,
    'voucher_number',coalesce(ct.data->>'voucherNumber',ct.data->>'voucher_number',ct.id),
    'transaction_date',coalesce(ct.data->>'transactionDate',ct.data->>'transaction_date',ct.created_at::text),
    'amount',public.erp_try_numeric(ct.data->>'amount',0),
    'currency',upper(coalesce(ct.data->>'currency','USD')),
    'type',lower(coalesce(ct.data->>'type','')),
    'notes',coalesce(ct.data->>'notes',''),
    'party_type',coalesce(ct.data->>'partyType',ct.data->>'party_type'),
    'party_id',coalesce(ct.data->>'partyId',ct.data->>'party_id'),
    'detached_from_order_id',coalesce(ct.data->>'detachedFromOrderId',ct.data->>'detached_from_order_id'),
    'detached_from_maintenance_order_id',coalesce(ct.data->>'detachedFromMaintenanceOrderId',ct.data->>'detached_from_maintenance_order_id'),
    'journal_entry_id',coalesce(ct.data->>'journalEntryId',ct.data->>'journal_entry_id')
  )
  from public.erp_cash_transactions ct
  where ct.company_id=p_company_id and not ct.is_deleted
    and public.erp_is_company_member(p_company_id)
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
    and coalesce((ct.data->>'unapplied')::boolean,false)
    and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))=lower(btrim(p_party_type))
    and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=coalesce(p_party_id,'')
    and upper(coalesce(ct.data->>'currency','USD'))=upper(coalesce(p_currency,'USD'))
  order by coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at) desc,ct.created_at desc;
$$;

create or replace function public.erp_update_partner_unapplied_payment(
  p_company_id uuid,
  p_transaction_id text,
  p_amount numeric,
  p_transaction_date timestamptz,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transaction public.erp_cash_transactions%rowtype;
  v_journal_id text;
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.update']
  );
  if coalesce(p_amount,0)<=0 then raise exception 'payment_amount_must_be_positive'; end if;
  if p_transaction_date is null then raise exception 'payment_date_required'; end if;

  select ct.* into v_transaction
  from public.erp_cash_transactions ct
  where ct.company_id=p_company_id and ct.id=p_transaction_id and not ct.is_deleted
  for update;
  if not found then raise exception 'partner_advance_not_found'; end if;
  if lower(coalesce(v_transaction.data->>'referenceType',v_transaction.data->>'reference_type',''))<>'partner_advance'
     or not coalesce((v_transaction.data->>'unapplied')::boolean,false) then
    raise exception 'transaction_is_not_unapplied_partner_payment';
  end if;

  v_journal_id:=coalesce(
    nullif(v_transaction.data->>'journalEntryId',''),
    nullif(v_transaction.data->>'journal_entry_id',''),
    nullif(v_transaction.data->>'entryId',''),
    nullif(v_transaction.data->>'entry_id','')
  );

  update public.erp_cash_transactions ct
  set data=ct.data||jsonb_build_object(
        'amount',p_amount,
        'transactionDate',p_transaction_date,
        'notes',coalesce(p_notes,''),
        'updatedAt',v_now,
        'unapplied',true,
        'referenceType','partner_advance'
      ),
      updated_at=v_now,
      updated_by=auth.uid()
  where ct.company_id=p_company_id and ct.id=p_transaction_id and not ct.is_deleted;

  if v_journal_id is not null then
    update public.erp_journal_entries je
    set data=je.data||jsonb_build_object(
          'entryDate',p_transaction_date,
          'totalDebit',p_amount,
          'totalCredit',p_amount,
          'description',coalesce(nullif(p_notes,''),je.data->>'description','Partner unapplied payment'),
          'updatedAt',v_now,
          'referenceType','partner_advance',
          'unapplied',true
        ),
        updated_at=v_now,
        updated_by=auth.uid()
    where je.company_id=p_company_id and je.id=v_journal_id and not je.is_deleted;

    update public.erp_journal_lines jl
    set data=jl.data||jsonb_build_object(
          'debit',case when public.erp_try_numeric(jl.data->>'debit',0)>0 then p_amount else 0 end,
          'credit',case when public.erp_try_numeric(jl.data->>'credit',0)>0 then p_amount else 0 end,
          'description',coalesce(p_notes,''),
          'referenceType','partner_advance',
          'unapplied',true,
          'updatedAt',v_now
        ),
        updated_at=v_now,
        updated_by=auth.uid()
    where jl.company_id=p_company_id and not jl.is_deleted
      and coalesce(jl.data->>'entryId',jl.data->>'entry_id')=v_journal_id;
  end if;

  return jsonb_build_object(
    'updated',true,'transactionId',p_transaction_id,'journalEntryId',v_journal_id,
    'amount',p_amount,'transactionDate',p_transaction_date
  );
end;
$$;

-- Global subledger totals now subtract preserved advances in the same original
-- currency. Negative balances are retained instead of silently discarding a
-- customer credit or supplier debit.
create or replace function public.erp_cloud_receivables_payables(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  with sales_docs as (
    select upper(coalesce(data->>'currency','USD')) currency,
      sum(greatest(public.erp_try_numeric(data->>'remainingAmount',0),0)) amount
    from public.erp_sales
    where company_id=p_company_id and not is_deleted
      and public.is_active_company_member(p_company_id)
    group by 1
  ), purchase_docs as (
    select upper(coalesce(data->>'currency','USD')) currency,
      sum(greatest(public.erp_try_numeric(
        data->>'remainingAmount',
        public.erp_try_numeric(data->>'totalAmount',0)-public.erp_try_numeric(data->>'paidAmount',0)
      ),0)) amount
    from public.erp_purchases
    where company_id=p_company_id and not is_deleted
      and public.is_active_company_member(p_company_id)
    group by 1
  ), customer_advances as (
    select upper(coalesce(data->>'currency','USD')) currency,
      sum(public.erp_try_numeric(data->>'amount',0)) amount
    from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='partner_advance'
      and coalesce((data->>'unapplied')::boolean,false)
      and lower(coalesce(data->>'partyType',data->>'party_type',''))='customer'
    group by 1
  ), supplier_advances as (
    select upper(coalesce(data->>'currency','USD')) currency,
      sum(public.erp_try_numeric(data->>'amount',0)) amount
    from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='partner_advance'
      and coalesce((data->>'unapplied')::boolean,false)
      and lower(coalesce(data->>'partyType',data->>'party_type',''))='supplier'
    group by 1
  ), currencies as (
    select currency from sales_docs union select currency from purchase_docs
    union select currency from customer_advances union select currency from supplier_advances
  ), receivables as (
    select c.currency,coalesce(s.amount,0)-coalesce(a.amount,0) amount
    from currencies c left join sales_docs s using(currency)
    left join customer_advances a using(currency)
  ), payables as (
    select c.currency,coalesce(p.amount,0)-coalesce(a.amount,0) amount
    from currencies c left join purchase_docs p using(currency)
    left join supplier_advances a using(currency)
  )
  select jsonb_build_object(
    'receivablesByCurrency',coalesce((select jsonb_object_agg(currency,amount) from receivables),'{}'::jsonb),
    'payablesByCurrency',coalesce((select jsonb_object_agg(currency,amount) from payables),'{}'::jsonb),
    'receivables',coalesce((select amount from receivables where currency='USD'),0),
    'payables',coalesce((select amount from payables where currency='USD'),0),
    'displayCurrency','USD','mixedCurrencyAggregationDisabled',true,
    'unappliedPartnerPaymentsIncluded',true
  );
$$;

create or replace function public.erp_cloud_partner_subledger_details_v2(
  p_company_id uuid,
  p_kind text
) returns table(
  party_id text,party_name text,currency text,document_count bigint,
  total_amount numeric,paid_amount numeric,outstanding_amount numeric,
  payment_count bigint,overdue_document_count bigint,
  oldest_due_date timestamptz,latest_document_date timestamptz
)
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'company_access_denied';
  end if;

  if lower(coalesce(p_kind,''))='receivables' then
    return query
    with docs as (
      select coalesce(s.data->>'customerId','') party_id,
        upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''),'USD')) currency,
        1::bigint document_count,
        greatest(public.erp_try_numeric(coalesce(s.data->>'totalAmount',s.data->>'salePrice'),0),0) total_amount,
        greatest(public.erp_try_numeric(s.data->>'paidAmount',0),0) paid_amount,
        greatest(public.erp_try_numeric(s.data->>'remainingAmount',0),0) outstanding_amount,
        (case when jsonb_typeof(s.data->'payments')='array' then jsonb_array_length(s.data->'payments') else 0 end)::bigint payment_count,
        case when coalesce(public.erp_try_timestamptz(s.data->>'dueDate',null),public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at)<now()
                  and public.erp_try_numeric(s.data->>'remainingAmount',0)>0 then 1 else 0 end::bigint overdue_count,
        coalesce(public.erp_try_timestamptz(s.data->>'dueDate',null),public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) due_date,
        coalesce(public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) document_date
      from public.erp_sales s
      where s.company_id=p_company_id and not s.is_deleted
        and public.erp_try_numeric(s.data->>'remainingAmount',0)>0
    ), advances as (
      select coalesce(ct.data->>'partyId',ct.data->>'party_id','') party_id,
        upper(coalesce(ct.data->>'currency','USD')) currency,
        0::bigint document_count,0::numeric total_amount,
        public.erp_try_numeric(ct.data->>'amount',0) paid_amount,
        -public.erp_try_numeric(ct.data->>'amount',0) outstanding_amount,
        1::bigint payment_count,0::bigint overdue_count,null::timestamptz due_date,
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at) document_date
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
        and coalesce((ct.data->>'unapplied')::boolean,false)
        and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))='customer'
    ), combined as (select * from docs union all select * from advances)
    select c.party_id,
      coalesce(nullif(cu.data->>'name',''),nullif(cu.data->>'fullName',''),'عميل غير مسمى') party_name,
      c.currency,sum(c.document_count)::bigint,sum(c.total_amount),sum(c.paid_amount),sum(c.outstanding_amount),
      sum(c.payment_count)::bigint,sum(c.overdue_count)::bigint,min(c.due_date),max(c.document_date)
    from combined c
    left join public.erp_customers cu on cu.company_id=p_company_id and cu.id::text=c.party_id and not cu.is_deleted
    where c.party_id<>''
    group by c.party_id,party_name,c.currency
    having abs(sum(c.outstanding_amount))>0.005 or sum(c.payment_count)>0
    order by c.currency,sum(c.outstanding_amount) desc,party_name;
    return;
  end if;

  if lower(coalesce(p_kind,''))='payables' then
    return query
    with docs as (
      select coalesce(p.data->>'supplierId','') party_id,
        upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''),'USD')) currency,
        1::bigint document_count,
        greatest(public.erp_try_numeric(p.data->>'totalAmount',0),0) total_amount,
        greatest(public.erp_try_numeric(p.data->>'paidAmount',0),0) paid_amount,
        greatest(public.erp_try_numeric(p.data->>'remainingAmount',public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)),0) outstanding_amount,
        (case when jsonb_typeof(p.data->'payments')='array' then jsonb_array_length(p.data->'payments') else 0 end)::bigint payment_count,
        case when coalesce(public.erp_try_timestamptz(p.data->>'dueDate',null),public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at)<now()
                  and public.erp_try_numeric(p.data->>'remainingAmount',public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0))>0 then 1 else 0 end::bigint overdue_count,
        coalesce(public.erp_try_timestamptz(p.data->>'dueDate',null),public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) due_date,
        coalesce(public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) document_date
      from public.erp_purchases p
      where p.company_id=p_company_id and not p.is_deleted
        and public.erp_try_numeric(p.data->>'remainingAmount',public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0))>0
    ), advances as (
      select coalesce(ct.data->>'partyId',ct.data->>'party_id','') party_id,
        upper(coalesce(ct.data->>'currency','USD')) currency,
        0::bigint document_count,0::numeric total_amount,
        public.erp_try_numeric(ct.data->>'amount',0) paid_amount,
        -public.erp_try_numeric(ct.data->>'amount',0) outstanding_amount,
        1::bigint payment_count,0::bigint overdue_count,null::timestamptz due_date,
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at) document_date
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
        and coalesce((ct.data->>'unapplied')::boolean,false)
        and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))='supplier'
    ), combined as (select * from docs union all select * from advances)
    select c.party_id,
      coalesce(nullif(sp.data->>'name',''),nullif(sp.data->>'companyName',''),'مورد غير مسمى') party_name,
      c.currency,sum(c.document_count)::bigint,sum(c.total_amount),sum(c.paid_amount),sum(c.outstanding_amount),
      sum(c.payment_count)::bigint,sum(c.overdue_count)::bigint,min(c.due_date),max(c.document_date)
    from combined c
    left join public.erp_suppliers sp on sp.company_id=p_company_id and sp.id::text=c.party_id and not sp.is_deleted
    where c.party_id<>''
    group by c.party_id,party_name,c.currency
    having abs(sum(c.outstanding_amount))>0.005 or sum(c.payment_count)>0
    order by c.currency,sum(c.outstanding_amount) desc,party_name;
    return;
  end if;

  raise exception 'unsupported_subledger_kind';
end;
$$;

create or replace function public.erp_cloud_partner_subledger_documents(
  p_company_id uuid,
  p_kind text,
  p_party_id text,
  p_currency text
) returns table(
  document_number text,document_date timestamptz,due_date timestamptz,
  currency text,total_amount numeric,paid_amount numeric,
  outstanding_amount numeric,payment_count bigint,is_overdue boolean,status text
)
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_active_company_member(p_company_id) then raise exception 'company_access_denied'; end if;

  if lower(coalesce(p_kind,''))='receivables' then
    return query
    select * from (
      select coalesce(nullif(s.data->>'invoiceNumber',''),nullif(s.data->>'saleNumber',''),nullif(s.data->>'documentNumber',''),'بدون رقم') document_number,
        coalesce(public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) document_date,
        coalesce(public.erp_try_timestamptz(s.data->>'dueDate',null),public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) due_date,
        upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''),'USD')) currency,
        greatest(public.erp_try_numeric(coalesce(s.data->>'totalAmount',s.data->>'salePrice'),0),0) total_amount,
        greatest(public.erp_try_numeric(s.data->>'paidAmount',0),0) paid_amount,
        greatest(public.erp_try_numeric(s.data->>'remainingAmount',0),0) outstanding_amount,
        (case when jsonb_typeof(s.data->'payments')='array' then jsonb_array_length(s.data->'payments') else 0 end)::bigint payment_count,
        coalesce(public.erp_try_timestamptz(s.data->>'dueDate',null),public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at)<now() is_overdue,
        coalesce(nullif(s.data->>'paymentStatus',''),nullif(s.data->>'status',''),'unpaid') status
      from public.erp_sales s
      where s.company_id=p_company_id and not s.is_deleted
        and coalesce(s.data->>'customerId','')=coalesce(p_party_id,'')
        and upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''),'USD'))=upper(coalesce(p_currency,'USD'))
        and public.erp_try_numeric(s.data->>'remainingAmount',0)>0
      union all
      select coalesce(ct.data->>'voucherNumber',ct.data->>'voucher_number',ct.id),
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at),
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at),
        upper(coalesce(ct.data->>'currency','USD')),0::numeric,
        public.erp_try_numeric(ct.data->>'amount',0),-public.erp_try_numeric(ct.data->>'amount',0),
        1::bigint,false,'unapplied_credit'::text
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
        and coalesce((ct.data->>'unapplied')::boolean,false)
        and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))='customer'
        and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=coalesce(p_party_id,'')
        and upper(coalesce(ct.data->>'currency','USD'))=upper(coalesce(p_currency,'USD'))
    ) x order by x.due_date,x.document_date,x.document_number;
    return;
  end if;

  if lower(coalesce(p_kind,''))='payables' then
    return query
    select * from (
      select coalesce(nullif(p.data->>'invoiceNumber',''),nullif(p.data->>'purchaseNumber',''),nullif(p.data->>'documentNumber',''),'بدون رقم') document_number,
        coalesce(public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) document_date,
        coalesce(public.erp_try_timestamptz(p.data->>'dueDate',null),public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) due_date,
        upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''),'USD')) currency,
        greatest(public.erp_try_numeric(p.data->>'totalAmount',0),0) total_amount,
        greatest(public.erp_try_numeric(p.data->>'paidAmount',0),0) paid_amount,
        greatest(public.erp_try_numeric(p.data->>'remainingAmount',public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)),0) outstanding_amount,
        (case when jsonb_typeof(p.data->'payments')='array' then jsonb_array_length(p.data->'payments') else 0 end)::bigint payment_count,
        coalesce(public.erp_try_timestamptz(p.data->>'dueDate',null),public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at)<now() is_overdue,
        coalesce(nullif(p.data->>'paymentStatus',''),nullif(p.data->>'status',''),'unpaid') status
      from public.erp_purchases p
      where p.company_id=p_company_id and not p.is_deleted
        and coalesce(p.data->>'supplierId','')=coalesce(p_party_id,'')
        and upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''),'USD'))=upper(coalesce(p_currency,'USD'))
        and public.erp_try_numeric(p.data->>'remainingAmount',public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0))>0
      union all
      select coalesce(ct.data->>'voucherNumber',ct.data->>'voucher_number',ct.id),
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at),
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at),
        upper(coalesce(ct.data->>'currency','USD')),0::numeric,
        public.erp_try_numeric(ct.data->>'amount',0),-public.erp_try_numeric(ct.data->>'amount',0),
        1::bigint,false,'unapplied_debit'::text
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
        and coalesce((ct.data->>'unapplied')::boolean,false)
        and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))='supplier'
        and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=coalesce(p_party_id,'')
        and upper(coalesce(ct.data->>'currency','USD'))=upper(coalesce(p_currency,'USD'))
    ) x order by x.due_date,x.document_date,x.document_number;
    return;
  end if;

  raise exception 'unsupported_subledger_kind';
end;
$$;

-- One recycle card per deletion batch. An exact archive id is carried to the
-- client so permanent delete cannot select the wrong row when identifiers are
-- repeated in different tables or deletion runs.
drop function if exists public.erp_recycle_bin_list(uuid,text,text);
create function public.erp_recycle_bin_list(
  p_company_id uuid,p_query text default '',p_entity_type text default ''
) returns table(
  archive_id text,entity_type text,record_id text,payload jsonb,
  deleted_at timestamptz,deleted_by text,source_table text,deletion_mode text,
  deletion_batch_id text,root_source_table text,root_record_id text,
  delete_reason text,related_count bigint
)
language sql
stable
security definer
set search_path=public
as $$
  with universal_source as (
    select u.*,
      count(*) over(partition by coalesce(u.deletion_batch_id::text,u.id::text)) related_count,
      row_number() over(
        partition by coalesce(u.deletion_batch_id::text,u.id::text)
        order by case
          when u.source_table=coalesce(u.root_source_table,u.source_table)
           and u.record_id=coalesce(u.root_record_id,u.record_id) then 0 else 1 end,
          u.deleted_at desc,u.id
      ) batch_rank
    from public.erp_universal_recycle_bin u
    where (u.company_id=p_company_id or u.company_id is null)
      and u.restored_at is null and u.purged_at is null
  ), universal as (
    select u.id::text archive_id,u.source_table entity_type,u.record_id,u.payload,u.deleted_at,
      coalesce(u.deleted_by::text,'') deleted_by,u.source_table,u.deletion_mode,
      u.deletion_batch_id::text,u.root_source_table,u.root_record_id,u.delete_reason,u.related_count
    from universal_source u where u.batch_rank=1
  ), company_context as (
    select c.slug from public.companies c where c.id=p_company_id
  ), legacy as (
    select null::text archive_id,r.entity_type,r.record_id,r.payload,r.deleted_at,
      coalesce(r.payload->>'deletedByUserName',r.payload->>'deletedBy','') deleted_by,
      'erp_records'::text source_table,'soft'::text deletion_mode,null::text deletion_batch_id,
      null::text root_source_table,null::text root_record_id,
      coalesce(r.payload->>'deleteReason','') delete_reason,1::bigint related_count
    from public.erp_records r cross join company_context c
    where r.company_id=c.slug and r.deleted_at is not null
  ), all_rows as (select * from universal union all select * from legacy)
  select x.* from all_rows x
  where public.is_company_member(p_company_id)
    and public.erp_cloud_user_has_permission(p_company_id,'settings.recycle_bin.view')
    and (coalesce(btrim(p_entity_type),'')='' or x.entity_type=btrim(p_entity_type))
    and (coalesce(btrim(p_query),'')='' or x.record_id ilike '%'||btrim(p_query)||'%'
      or x.entity_type ilike '%'||btrim(p_query)||'%'
      or coalesce(x.root_record_id,'') ilike '%'||btrim(p_query)||'%'
      or x.payload::text ilike '%'||btrim(p_query)||'%')
  order by x.deleted_at desc;
$$;

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
  v_row record;
  v_pk text;
  v_has_company_id boolean;
  v_has_company_camel boolean;
  v_actual integer:=0;
  v_archives integer:=0;
  v_progress integer;
  v_remaining integer;
begin
  if not public.is_company_member(p_company_id) then raise exception 'access_denied'; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'settings.recycle_bin.purge') then
    raise exception 'permanent_delete_permission_required';
  end if;

  select u.* into v_archive
  from public.erp_universal_recycle_bin u
  where u.id=p_archive_id and (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null and u.purged_at is null
  for update;
  if not found then raise exception 'deleted_record_not_found'; end if;
  v_batch:=v_archive.deletion_batch_id;
  perform set_config('qualityline.recycle_purge','on',true);

  drop table if exists pg_temp.erp_v72_purge_queue;
  create temporary table pg_temp.erp_v72_purge_queue(
    archive_id uuid primary key,source_table text,record_id text,priority integer
  ) on commit drop;

  insert into pg_temp.erp_v72_purge_queue(archive_id,source_table,record_id,priority)
  select u.id,u.source_table,u.record_id,
    case
      when u.source_table in ('erp_journal_lines','erp_inventory_fifo_consumptions') then 10
      when u.source_table in ('erp_maintenance_payments','erp_maintenance_parts','erp_sales_order_items_cloud','erp_purchase_order_items_cloud','erp_warehouse_transfer_items','erp_asset_depreciation_entries') then 20
      when u.source_table in ('erp_inventory_movements','erp_inventory_movements_cloud','erp_inventory_cost_layers','erp_cash_transactions') then 30
      when u.source_table in ('erp_commercial_workflow_documents','erp_journal_entries','erp_cloud_journals') then 40
      when u.source_table in ('erp_sales_orders_cloud','erp_purchase_orders_cloud','erp_maintenance_orders','erp_warehouse_transfers','erp_fixed_assets') then 60
      else 50 end
  from public.erp_universal_recycle_bin u
  where (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null and u.purged_at is null
    and (u.id=v_archive.id or (v_batch is not null and u.deletion_batch_id=v_batch));

  loop
    v_progress:=0;
    for v_row in select * from pg_temp.erp_v72_purge_queue order by priority,archive_id
    loop
      begin
        if to_regclass(format('public.%I',v_row.source_table)) is not null then
          select case
            when exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='id') then 'id'
            when exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='record_id') then 'record_id'
            else null end into v_pk;
          if v_pk is not null then
            select exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='company_id') into v_has_company_id;
            select exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='companyId') into v_has_company_camel;
            if v_has_company_id then
              execute format('delete from public.%I where %I::text=$1 and company_id::text=$2',v_row.source_table,v_pk)
                using v_row.record_id,p_company_id::text;
            elsif v_has_company_camel then
              execute format('delete from public.%I where %I::text=$1 and "companyId"::text=$2',v_row.source_table,v_pk)
                using v_row.record_id,p_company_id::text;
            else
              execute format('delete from public.%I where %I::text=$1',v_row.source_table,v_pk)
                using v_row.record_id;
            end if;
            v_actual:=v_actual+1;
          end if;
        end if;
        delete from pg_temp.erp_v72_purge_queue where archive_id=v_row.archive_id;
        v_progress:=v_progress+1;
      exception when foreign_key_violation then
        null;
      end;
    end loop;

    select count(*) into v_remaining from pg_temp.erp_v72_purge_queue;
    exit when v_remaining=0;
    if v_progress=0 then
      raise exception 'permanent_delete_blocked_by_active_relationships';
    end if;
  end loop;

  delete from public.erp_universal_recycle_bin u
  where (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null and u.purged_at is null
    and (u.id=v_archive.id or (v_batch is not null and u.deletion_batch_id=v_batch));
  get diagnostics v_archives=row_count;

  return jsonb_build_object(
    'purged',v_archives>0,'archiveId',p_archive_id,'deletionBatchId',v_batch,
    'archiveRowsRemoved',v_archives,'sourceRowsProcessed',v_actual,'batchPurged',v_batch is not null
  );
end;
$$;

create or replace function public.erp_recycle_bin_purge(
  p_company_id uuid,
  p_entity_type text,
  p_record_id text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_archive_id uuid;
  v_slug text;
  v_deleted integer;
begin
  if not public.is_company_member(p_company_id) then raise exception 'access_denied'; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'settings.recycle_bin.purge') then
    raise exception 'permanent_delete_permission_required';
  end if;

  select c.slug into v_slug from public.companies c where c.id=p_company_id;
  perform set_config('qualityline.recycle_purge','on',true);
  delete from public.erp_records r
  where r.company_id=v_slug and r.entity_type=btrim(p_entity_type)
    and r.record_id=btrim(p_record_id) and r.deleted_at is not null;
  get diagnostics v_deleted=row_count;
  if v_deleted>0 then
    return jsonb_build_object('purged',true,'legacy',true,'deletedRows',v_deleted);
  end if;

  select u.id into v_archive_id
  from public.erp_universal_recycle_bin u
  where u.source_table=btrim(p_entity_type) and u.record_id=btrim(p_record_id)
    and (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null and u.purged_at is null
  order by u.deleted_at desc limit 1;
  if v_archive_id is null then raise exception 'deleted_record_not_found'; end if;
  return public.erp_recycle_bin_purge_by_archive(p_company_id,v_archive_id);
end;
$$;

revoke all on function public.erp_delete_inventory_warehouse_transfer_v2(uuid,text,text) from public,anon;
revoke all on function public.erp_delete_cloud_sales_order_v2(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_purchase_order_v2(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_maintenance_order_v2(uuid,uuid,text) from public,anon;
revoke all on function public.erp_list_partner_unapplied_payments(uuid,text,text,text) from public,anon;
revoke all on function public.erp_update_partner_unapplied_payment(uuid,text,numeric,timestamptz,text) from public,anon;
revoke all on function public.erp_recycle_bin_list(uuid,text,text) from public,anon;
revoke all on function public.erp_recycle_bin_purge_by_archive(uuid,uuid) from public,anon;
revoke all on function public.erp_recycle_bin_purge(uuid,text,text) from public,anon;

grant execute on function public.erp_delete_inventory_warehouse_transfer_v2(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_sales_order_v2(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_purchase_order_v2(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_maintenance_order_v2(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_list_partner_unapplied_payments(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_update_partner_unapplied_payment(uuid,text,numeric,timestamptz,text) to authenticated,service_role;
grant execute on function public.erp_cloud_receivables_payables(uuid) to authenticated,service_role;
grant execute on function public.erp_cloud_partner_subledger_details_v2(uuid,text) to authenticated,service_role;
grant execute on function public.erp_cloud_partner_subledger_documents(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_recycle_bin_list(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_recycle_bin_purge_by_archive(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_recycle_bin_purge(uuid,text,text) to authenticated,service_role;
