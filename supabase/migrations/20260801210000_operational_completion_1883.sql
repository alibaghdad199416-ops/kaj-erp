begin;

-- Hierarchical cash-flow report: Cash In first, Cash Out second, with the
-- complete ledger account ancestry and journal/source references at leaves.
create or replace function public.erp_cloud_cash_flow_hierarchy(
  p_company_id uuid,
  p_currency text default 'ALL',
  p_branch_id text default null,
  p_cost_center_id text default null,
  p_from_date timestamptz default null,
  p_to_date timestamptz default null
) returns setof jsonb
language sql
security definer
set search_path = public
as $$
with recursive account_tree as (
  select
    a.account_id,
    a.parent_account_id,
    a.code,
    a.name,
    a.account_type,
    a.currency,
    array[a.account_id]::text[] id_path,
    array[coalesce(a.name,'')]::text[] name_path,
    array[coalesce(a.code,'')]::text[] code_path,
    0 hierarchy_depth,
    a.code root_account_code,
    a.name root_account_name
  from public.erp_accounts a
  where a.organization_id = p_company_id
    and a.is_active
    and (
      a.parent_account_id is null
      or not exists (
        select 1
        from public.erp_accounts parent
        where parent.organization_id = a.organization_id
          and parent.account_id = a.parent_account_id
          and parent.is_active
      )
    )
  union all
  select
    child.account_id,
    child.parent_account_id,
    child.code,
    child.name,
    child.account_type,
    child.currency,
    tree.id_path || child.account_id,
    tree.name_path || coalesce(child.name,''),
    tree.code_path || coalesce(child.code,''),
    tree.hierarchy_depth + 1,
    tree.root_account_code,
    tree.root_account_name
  from public.erp_accounts child
  join account_tree tree
    on child.organization_id = p_company_id
   and child.parent_account_id = tree.account_id
  where child.is_active
    and not child.account_id = any(tree.id_path)
), cash_rows as (
  select
    ct.*,
    lower(coalesce(ct.data->>'type','')) movement_type,
    public.erp_try_numeric(ct.data->>'amount',0::numeric) amount,
    public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at) movement_date,
    coalesce(ct.data->>'cashAccountId',ct.data->>'cash_account_id','') cash_account_id,
    lower(coalesce(ct.data->>'category',ct.data->>'referenceType','')) category_key
  from public.erp_cash_transactions ct
  where ct.company_id = p_company_id
    and not ct.is_deleted
    and public.is_active_company_member(p_company_id)
    and (
      upper(p_currency) = 'ALL'
      or upper(coalesce(nullif(ct.data->>'currency',''),'IQD')) = upper(p_currency)
    )
    and (
      p_branch_id is null
      or coalesce(ct.data->>'branchId',ct.data->>'branch_id') = p_branch_id
    )
    and (
      p_cost_center_id is null
      or coalesce(ct.data->>'costCenterId',ct.data->>'cost_center_id') = p_cost_center_id
    )
    and (
      p_from_date is null
      or public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at) >= p_from_date
    )
    and (
      p_to_date is null
      or public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at) <= p_to_date
    )
), resolved as (
  select
    row.*,
    cash_account.data cash_account_data,
    tree.account_id ledger_account_id,
    tree.parent_account_id ledger_parent_account_id,
    tree.code ledger_account_code,
    tree.name ledger_account_name,
    tree.account_type ledger_account_type,
    tree.name_path ledger_name_path,
    tree.hierarchy_depth ledger_hierarchy_depth,
    tree.root_account_code,
    tree.root_account_name
  from cash_rows row
  left join public.erp_cash_accounts cash_account
    on cash_account.company_id = p_company_id
   and cash_account.id = row.cash_account_id
   and not cash_account.is_deleted
  left join account_tree tree
    on tree.account_id = coalesce(
      cash_account.data->>'accountId',
      cash_account.data->>'account_id',
      row.data->>'accountId',
      row.data->>'account_id'
    )
)
select jsonb_build_object(
  'entryDate', resolved.movement_date,
  'entryNumber', coalesce(
    nullif(resolved.data->>'journalEntryNumber',''),
    nullif(resolved.data->>'entryNumber',''),
    nullif(resolved.data->>'voucherNumber',''),
    resolved.id
  ),
  'flowDirection', case
    when resolved.movement_type in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then 'in'
    when resolved.movement_type in ('expense','payment','out','cash_out','supplier_payment','transfer_out') then 'out'
    else case when resolved.amount >= 0 then 'in' else 'out' end
  end,
  'flowSection', case
    when resolved.category_key similar to '%(capital|loan|financ|transfer|رأس|تمويل|قرض|تحويل)%' then 'financing'
    when resolved.category_key similar to '%(asset|fixed_asset|investment|أصل|اصول|أصول|استثمار)%' then 'investing'
    else 'operating'
  end,
  'cashAccountId', resolved.cash_account_id,
  'accountId', coalesce(resolved.ledger_account_id,''),
  'parentAccountId', coalesce(resolved.ledger_parent_account_id,''),
  'accountCode', coalesce(resolved.ledger_account_code,''),
  'accountName', coalesce(
    nullif(resolved.ledger_account_name,''),
    nullif(resolved.cash_account_data->>'name',''),
    nullif(resolved.data->>'accountName',''),
    'حساب نقدي غير مصنف'
  ),
  'accountType', coalesce(resolved.ledger_account_type,'asset'),
  'rootAccountCode', coalesce(resolved.root_account_code,resolved.ledger_account_code,''),
  'rootAccountName', coalesce(
    resolved.root_account_name,
    resolved.ledger_account_name,
    resolved.cash_account_data->>'name',
    resolved.data->>'accountName',
    'حساب نقدي غير مصنف'
  ),
  'hierarchyPath', case
    when resolved.ledger_name_path is not null
      then array_to_string(resolved.ledger_name_path,' / ')
    else coalesce(
      nullif(resolved.cash_account_data->>'name',''),
      nullif(resolved.data->>'accountName',''),
      'حساب نقدي غير مصنف'
    )
  end,
  'hierarchyDepth', coalesce(resolved.ledger_hierarchy_depth,0),
  'description', coalesce(
    resolved.data->>'description',
    resolved.data->>'notes',
    resolved.data->>'category',
    ''
  ),
  'partyName', coalesce(resolved.data->>'partyName',resolved.data->>'counterpartyName',''),
  'paymentMethod', coalesce(resolved.data->>'paymentMethod',''),
  'referenceType', coalesce(
    resolved.data->>'referenceType',
    resolved.data->>'sourceType',
    resolved.data->>'journalReferenceType',
    ''
  ),
  'referenceId', coalesce(
    resolved.data->>'journalEntryId',
    resolved.data->>'referenceId',
    resolved.data->>'sourceId',
    resolved.id
  ),
  'currency', upper(coalesce(nullif(resolved.data->>'currency',''),'IQD')),
  'debit', case
    when resolved.movement_type in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then abs(resolved.amount)
    else 0
  end,
  'credit', case
    when resolved.movement_type in ('expense','payment','out','cash_out','supplier_payment','transfer_out') then abs(resolved.amount)
    else 0
  end,
  'cashIn', case
    when resolved.movement_type in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then abs(resolved.amount)
    else 0
  end,
  'cashOut', case
    when resolved.movement_type in ('expense','payment','out','cash_out','supplier_payment','transfer_out') then abs(resolved.amount)
    else 0
  end,
  'netCashFlow', case
    when resolved.movement_type in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then abs(resolved.amount)
    when resolved.movement_type in ('expense','payment','out','cash_out','supplier_payment','transfer_out') then -abs(resolved.amount)
    else resolved.amount
  end
)
from resolved
order by
  case
    when resolved.movement_type in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then 0
    else 1
  end,
  coalesce(resolved.ledger_name_path,array[coalesce(resolved.cash_account_data->>'name',resolved.data->>'accountName','')]),
  resolved.movement_date,
  resolved.created_at;
$$;


-- One authoritative vehicle projection. It resolves the current warehouse from
-- current/historical aliases and, when needed, from the latest transfer. This
-- removes three client round-trips and makes warehouse filtering deterministic.
create or replace function public.erp_list_cloud_cars_with_warehouse(
  p_company_id uuid
) returns setof jsonb
language sql
security definer
set search_path = public
as $$
select
  c.data
  || jsonb_build_object(
    'id', c.id,
    'warehouseId', resolved.canonical_warehouse_id,
    'warehouse_id', resolved.canonical_warehouse_id,
    'currentWarehouseId', resolved.canonical_warehouse_id,
    'current_warehouse_id', resolved.canonical_warehouse_id,
    'warehouseCode', coalesce(resolved.warehouse_code,''),
    'warehouseName', coalesce(resolved.warehouse_name,'')
  )
from public.erp_cars c
left join lateral (
  select
    t.data->>'fromWarehouseId' from_warehouse_id,
    t.data->>'toWarehouseId' to_warehouse_id,
    lower(coalesce(t.data->>'status','completed')) transfer_status
  from public.erp_car_warehouse_transfers t
  where t.company_id = c.company_id
    and not t.is_deleted
    and coalesce(t.data->>'carId',t.data->>'car_id') = c.id
  order by
    public.erp_try_timestamptz(t.data->>'transferDate',t.created_at) desc,
    t.created_at desc
  limit 1
) latest on true
left join lateral (
  select coalesce(
    nullif(btrim(c.data->>'warehouseId'),''),
    nullif(btrim(c.data->>'warehouse_id'),''),
    nullif(btrim(c.data->>'currentWarehouseId'),''),
    nullif(btrim(c.data->>'current_warehouse_id'),''),
    nullif(btrim(c.data->>'lastWarehouseId'),''),
    nullif(btrim(c.data->>'last_warehouse_id'),''),
    nullif(btrim(c.data->>'warehouseCode'),''),
    nullif(btrim(c.data->>'warehouseName'),''),
    case when latest.transfer_status = 'reversed'
      then nullif(btrim(latest.from_warehouse_id),'')
      else nullif(btrim(latest.to_warehouse_id),'')
    end
  ) reference
) candidate on true
left join lateral (
  select w.id,w.data->>'code' code,w.data->>'name' name
  from public.erp_warehouses w
  where w.company_id = c.company_id
    and not w.is_deleted
    and (
      w.id = candidate.reference
      or lower(btrim(coalesce(w.data->>'code',''))) = lower(btrim(candidate.reference))
      or lower(btrim(coalesce(w.data->>'name',''))) = lower(btrim(candidate.reference))
      or regexp_replace(lower(coalesce(w.data->>'code','') || coalesce(w.data->>'name','')), '[[:space:][:punct:]]+', '', 'g')
         = regexp_replace(lower(coalesce(candidate.reference,'')), '[[:space:][:punct:]]+', '', 'g')
    )
  order by case when w.id = candidate.reference then 0 else 1 end
  limit 1
) warehouse on true
left join lateral (
  select
    coalesce(warehouse.id,candidate.reference) canonical_warehouse_id,
    warehouse.code warehouse_code,
    warehouse.name warehouse_name
) resolved on true
where c.company_id = p_company_id
  and not c.is_deleted
  and public.is_active_company_member(p_company_id)
order by c.created_at desc;
$$;

create index if not exists erp_cash_transactions_report_lookup_idx
  on public.erp_cash_transactions(
    company_id,
    (data->>'cashAccountId'),
    (data->>'transactionDate')
  )
  where not is_deleted;

create index if not exists erp_accounts_hierarchy_active_idx
  on public.erp_accounts(organization_id,parent_account_id,account_id)
  where is_active;

revoke all on function public.erp_cloud_cash_flow_hierarchy(uuid,text,text,text,timestamptz,timestamptz) from public,anon;
grant execute on function public.erp_cloud_cash_flow_hierarchy(uuid,text,text,text,timestamptz,timestamptz) to authenticated;
revoke all on function public.erp_list_cloud_cars_with_warehouse(uuid) from public,anon;
grant execute on function public.erp_list_cloud_cars_with_warehouse(uuid) to authenticated;
commit;
