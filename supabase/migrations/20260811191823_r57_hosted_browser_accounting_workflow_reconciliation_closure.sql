begin;

-- R57 is forward-only. Account codes are identifiers: numeric-looking legacy
-- values are repaired without floating point conversion and collisions abort
-- the migration before any row is changed.
create or replace function public.erp_r57_canonical_account_code(p_code text)
returns text language plpgsql immutable strict set search_path=public as $$
declare v text:=btrim(p_code); whole text; fraction text; rounded bigint;
begin
  if v !~ '^[0-9]+\.[0-9]+$' then return v; end if;
  whole:=split_part(v,'.',1); fraction:=split_part(v,'.',2);
  if fraction ~ '^0+$' then return whole; end if;
  if length(fraction)<=2 then return whole||rpad(fraction,2,'0'); end if;
  rounded:=round(('0.'||fraction)::numeric*100)::bigint;
  if rounded=100 then return (whole::numeric+1)::text||'00'; end if;
  return whole||lpad(rounded::text,2,'0');
end $$;

do $$
begin
  if exists(
    select 1 from public.erp_accounts
    group by organization_id,public.erp_r57_canonical_account_code(code)
    having count(*)>1 and bool_or(code is distinct from public.erp_r57_canonical_account_code(code))
  ) then
    raise exception 'r57_account_code_repair_collision';
  end if;
  update public.erp_accounts
     set code=public.erp_r57_canonical_account_code(code)
   where code is distinct from public.erp_r57_canonical_account_code(code);
end $$;

create or replace function public.erp_r57_accounting_header_snapshot(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  with currencies(code) as (values('USD'),('IQD')),
  cash as (
    select c.code,
      coalesce(sum(public.erp_try_numeric(coalesce(a.data->>'openingBalance',a.data->>'opening_balance'),0)),0)
      +coalesce((select sum(case
        when lower(coalesce(t.data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
          then abs(public.erp_try_numeric(t.data->>'amount',0))
        when lower(coalesce(t.data->>'type','')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out')
          then -abs(public.erp_try_numeric(t.data->>'amount',0)) else 0 end)
        from public.erp_cash_transactions t
        where t.company_id=p_company_id and not t.is_deleted
          and upper(coalesce(t.data->>'currency',''))=c.code),0) balance
    from currencies c left join public.erp_cash_accounts a
      on a.company_id=p_company_id and not a.is_deleted
     and coalesce((a.data->>'isActive')::boolean,true)
     and upper(coalesce(a.data->>'currency',''))=c.code
    group by c.code
  )
  select jsonb_build_object(
    'accountCount',(select count(*) from public.erp_accounts where organization_id=p_company_id and is_active),
    'entryCount',(select count(*) from public.erp_journal_entries where company_id=p_company_id and not is_deleted),
    'cashByCurrency',jsonb_object_agg(code,balance)
  ) into result from cash;
  return result;
end $$;

create table if not exists public.erp_r57_workflow_discrepancies(
  company_id uuid not null,
  module text not null check(module in('purchases','sales','maintenance')),
  parent_id uuid not null,
  item_id text not null,
  status text not null check(status in('open','resolved')),
  ordered_quantity numeric not null,
  operational_quantity numeric not null,
  invoiced_quantity numeric not null,
  opened_at timestamptz not null default now(),
  resolved_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(company_id,module,parent_id,item_id)
);
alter table public.erp_r57_workflow_discrepancies enable row level security;
drop policy if exists erp_r57_workflow_discrepancies_tenant on public.erp_r57_workflow_discrepancies;
create policy erp_r57_workflow_discrepancies_tenant on public.erp_r57_workflow_discrepancies
  for select to authenticated using(public.erp_is_company_member(company_id));

create or replace function public.erp_r57_commercial_reconciliation(
  p_company_id uuid,p_order_id uuid,p_module text
) returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if p_module not in('purchases','sales') then raise exception 'r57_invalid_module'; end if;
  return query
  with ordered as (
    select i.item_id,i.description,i.quantity::numeric ordered
    from public.erp_purchase_order_items_cloud i
    where p_module='purchases' and i.company_id=p_company_id and i.order_id=p_order_id and not i.is_deleted
    union all
    select i.item_id,i.description,i.quantity::numeric
    from public.erp_sales_order_items_cloud i
    where p_module='sales' and i.company_id=p_company_id and i.order_id=p_order_id and not i.is_deleted
  ), docs as (
    select d.document_type,d.status,a.value
    from public.erp_commercial_workflow_documents d
    cross join lateral jsonb_array_elements(coalesce(d.payload->'allocations','[]'::jsonb)) a(value)
    where d.company_id=p_company_id and d.parent_id=p_order_id and d.module=p_module and not d.is_deleted
  ), totals as (
    select coalesce(value->>'itemId',value->>'item_id') item_id,
      sum(case when status='approved' and document_type in('receipt','delivery') then public.erp_try_numeric(value->>'quantity',0) else 0 end) operational,
      sum(case when status='approved' and document_type='invoice' then public.erp_try_numeric(value->>'quantity',0) else 0 end) invoiced
    from docs group by 1
  )
  select jsonb_build_object('itemId',o.item_id,'description',o.description,
    'orderedQuantity',o.ordered,'operationalQuantity',coalesce(t.operational,0),
    'invoicedQuantity',coalesce(t.invoiced,0),
    'remainingOperational',greatest(o.ordered-coalesce(t.operational,0),0),
    'remainingInvoice',greatest(coalesce(t.operational,0)-coalesce(t.invoiced,0),0),
    'status',case when coalesce(t.operational,0)=o.ordered and coalesce(t.invoiced,0)=o.ordered then 'reconciled'
                  when coalesce(t.operational,0)=0 then 'pending' else 'partial' end)
  from ordered o left join totals t on t.item_id=o.item_id order by o.description,o.item_id;
end $$;

create or replace function public.erp_r57_guard_commercial_document_quantities()
returns trigger language plpgsql security invoker set search_path=public as $$
declare a jsonb; ordered numeric; already numeric; v_item text; qty numeric; boundary text;
begin
  if new.is_deleted or new.status<>'approved' or old.status='approved' then return new; end if;
  for a in select value from jsonb_array_elements(coalesce(new.payload->'allocations','[]'::jsonb)) loop
    v_item:=coalesce(a->>'itemId',a->>'item_id'); qty:=public.erp_try_numeric(a->>'quantity',-1);
    if v_item is null or qty<=0 then raise exception 'r57_invalid_quantity item=% quantity=%',coalesce(v_item,'<missing>'),qty; end if;
    if new.module='purchases' then
      select quantity::numeric into ordered from public.erp_purchase_order_items_cloud
       where company_id=new.company_id and order_id=new.parent_id and item_id=v_item and not is_deleted;
    elsif new.module='sales' then
      select quantity::numeric into ordered from public.erp_sales_order_items_cloud
       where company_id=new.company_id and order_id=new.parent_id and item_id=v_item and not is_deleted;
    else continue; end if;
    if ordered is null then raise exception 'r57_unknown_order_item item=%',v_item; end if;
    boundary:=case when new.document_type='invoice' then 'invoice' else 'operational' end;
    select coalesce(sum(public.erp_try_numeric(x.value->>'quantity',0)),0) into already
      from public.erp_commercial_workflow_documents d
      cross join lateral jsonb_array_elements(coalesce(d.payload->'allocations','[]'::jsonb)) x(value)
     where d.company_id=new.company_id and d.parent_id=new.parent_id and d.module=new.module
       and d.status='approved' and not d.is_deleted and d.id<>new.id
       and coalesce(x.value->>'itemId',x.value->>'item_id')=v_item
       and (case when boundary='invoice' then d.document_type='invoice' else d.document_type in('receipt','delivery') end);
    if already+qty>ordered then
      raise exception 'r57_quantity_exceeds_order item=% ordered=% already=% attempted=%',v_item,ordered,already,qty;
    end if;
    if boundary='invoice' then
      select coalesce(sum(public.erp_try_numeric(x.value->>'quantity',0)),0) into ordered
        from public.erp_commercial_workflow_documents d
        cross join lateral jsonb_array_elements(coalesce(d.payload->'allocations','[]'::jsonb)) x(value)
       where d.company_id=new.company_id and d.parent_id=new.parent_id and d.module=new.module
         and d.status='approved' and not d.is_deleted and d.document_type in('receipt','delivery')
         and coalesce(x.value->>'itemId',x.value->>'item_id')=v_item;
      if already+qty>ordered then
        raise exception 'r57_invoice_exceeds_approved_operational item=% available=% already=% attempted=%',v_item,ordered,already,qty;
      end if;
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists erp_r57_commercial_quantity_guard on public.erp_commercial_workflow_documents;
create trigger erp_r57_commercial_quantity_guard before update of status on public.erp_commercial_workflow_documents
for each row execute function public.erp_r57_guard_commercial_document_quantities();

create unique index if not exists erp_r57_notification_event_uq
  on public.erp_enterprise_notifications(company_id,(data->>'eventKey'))
  where not is_deleted and nullif(data->>'eventKey','') is not null;

create or replace function public.erp_r57_refresh_commercial_discrepancies()
returns trigger language plpgsql security definer set search_path=public as $$
declare r jsonb; next_status text; previous_status text; event_key text; target_user text;
begin
  if new.module not in('purchases','sales') then return new; end if;
  target_user:=public.erp_r49_notification_user_key();
  for r in select * from public.erp_r57_commercial_reconciliation(new.company_id,new.parent_id,new.module) loop
    next_status:=case when r->>'status'='reconciled' then 'resolved' else 'open' end;
    select status into previous_status from public.erp_r57_workflow_discrepancies
     where company_id=new.company_id and module=new.module and parent_id=new.parent_id and item_id=r->>'itemId';
    insert into public.erp_r57_workflow_discrepancies(
      company_id,module,parent_id,item_id,status,ordered_quantity,operational_quantity,invoiced_quantity,resolved_at,updated_at
    ) values(new.company_id,new.module,new.parent_id,r->>'itemId',next_status,
      (r->>'orderedQuantity')::numeric,(r->>'operationalQuantity')::numeric,(r->>'invoicedQuantity')::numeric,
      case when next_status='resolved' then now() end,now())
    on conflict(company_id,module,parent_id,item_id) do update set
      status=excluded.status,ordered_quantity=excluded.ordered_quantity,
      operational_quantity=excluded.operational_quantity,invoiced_quantity=excluded.invoiced_quantity,
      resolved_at=case when excluded.status='resolved' then coalesce(erp_r57_workflow_discrepancies.resolved_at,now()) else null end,
      updated_at=now();
    if previous_status is distinct from next_status and target_user is not null then
      event_key:=format('r57:%s:%s:%s:%s:%s',new.module,new.parent_id,r->>'itemId',next_status,new.id);
      insert into public.erp_enterprise_notifications(company_id,id,data)
      values(new.company_id,gen_random_uuid(),jsonb_build_object(
        'userId',target_user,'titleAr',case when next_status='resolved' then 'اكتملت مطابقة كميات المستند' else 'يوجد فرق في كميات سير العمل' end,
        'titleEn',case when next_status='resolved' then 'Document quantities reconciled' else 'Workflow quantity discrepancy' end,
        'bodyAr',coalesce(r->>'description',r->>'itemId'),'bodyEn',coalesce(r->>'description',r->>'itemId'),
        'type',case when next_status='resolved' then 'info' else 'warning' end,
        'module',new.module,'event','quantity_reconciliation','status',next_status,
        'referenceType',case when new.module='purchases' then 'purchase_order' else 'sales_order' end,
        'referenceId',new.parent_id::text,'eventKey',event_key,'createdAt',now()
      )) on conflict do nothing;
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists erp_r57_commercial_discrepancy_refresh on public.erp_commercial_workflow_documents;
create trigger erp_r57_commercial_discrepancy_refresh
after insert or update of status,is_deleted on public.erp_commercial_workflow_documents
for each row execute function public.erp_r57_refresh_commercial_discrepancies();

revoke all on function public.erp_r57_canonical_account_code(text) from public,anon;
revoke all on function public.erp_r57_accounting_header_snapshot(uuid) from public,anon;
revoke all on function public.erp_r57_commercial_reconciliation(uuid,uuid,text) from public,anon;
grant execute on function public.erp_r57_accounting_header_snapshot(uuid) to authenticated,service_role;
grant execute on function public.erp_r57_commercial_reconciliation(uuid,uuid,text) to authenticated,service_role;
grant select on public.erp_r57_workflow_discrepancies to authenticated;

commit;
