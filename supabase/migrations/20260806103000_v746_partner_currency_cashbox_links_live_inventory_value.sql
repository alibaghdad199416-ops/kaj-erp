begin;

-- V7.4.6: exact partner-currency ledgers, user-owned reciprocal cashbox links,
-- automatic FX-payment routing, and live inventory valuation from remaining stock.

create or replace function public.erp_workflow_partner_account(
  p_company_id uuid,p_partner_type text,p_partner_id text,p_currency text
) returns text language plpgsql security definer set search_path=public as $$
declare
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_id text;
begin
  if v_currency not in ('USD','IQD') then raise exception 'unsupported_partner_currency:%',v_currency; end if;
  select case when v_currency='IQD' then pa.iqd_account_id else pa.usd_account_id end
    into v_id
  from public.erp_partner_accounts pa
  where pa.organization_id=p_company_id and pa.partner_type=lower(p_partner_type)
    and pa.partner_id=p_partner_id and pa.is_active
  limit 1;
  if v_id is null or not exists(
    select 1 from public.erp_accounts a where a.organization_id=p_company_id
      and a.account_id=v_id and a.is_active and upper(a.currency)=v_currency
  ) then
    if lower(p_partner_type)='customer' then
      update public.erp_customers set data=data,updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=p_partner_id and not is_deleted;
    elsif lower(p_partner_type)='supplier' then
      update public.erp_suppliers set data=data,updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=p_partner_id and not is_deleted;
    else
      raise exception 'invalid_partner_type';
    end if;
    select case when v_currency='IQD' then pa.iqd_account_id else pa.usd_account_id end
      into v_id from public.erp_partner_accounts pa
    where pa.organization_id=p_company_id and pa.partner_type=lower(p_partner_type)
      and pa.partner_id=p_partner_id and pa.is_active limit 1;
  end if;
  if v_id is null or not exists(
    select 1 from public.erp_accounts a where a.organization_id=p_company_id
      and a.account_id=v_id and a.is_active and upper(a.currency)=v_currency
  ) then raise exception 'partner_currency_account_missing:%',v_currency; end if;
  return v_id;
end $$;

create or replace function public.erp_resolve_linked_cash_account(
  p_company_id uuid,p_source_cash_account_id text,p_target_currency text
) returns text language plpgsql security definer set search_path=public as $$
declare v_target text; v_currency text:=upper(p_target_currency);
begin
  select l.target_cash_account_id into v_target
  from public.erp_cash_account_links l
  join public.erp_cash_accounts c on c.company_id=l.company_id and c.id=l.target_cash_account_id
  where l.company_id=p_company_id and l.source_cash_account_id=p_source_cash_account_id
    and not c.is_deleted and public.erp_try_boolean(coalesce(c.data->>'isActive',c.data->>'is_active'),'true')
    and upper(coalesce(c.data->>'currency',''))=v_currency
  limit 1;
  if v_target is null then
    select nullif(coalesce(c.data->>'linked_cash_account_id',c.data->>'linkedCashAccountId'),'') into v_target
    from public.erp_cash_accounts c where c.company_id=p_company_id and c.id=p_source_cash_account_id and not c.is_deleted;
    if v_target is not null and not exists(
      select 1 from public.erp_cash_accounts t where t.company_id=p_company_id and t.id=v_target and not t.is_deleted
      and upper(coalesce(t.data->>'currency',''))=v_currency
    ) then v_target:=null; end if;
  end if;
  return v_target;
end $$;

create or replace function public.erp_rebuild_live_inventory_values(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_updated integer:=0; v_total numeric:=0;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'access denied'; end if;
  with costs as (
    select item_id,warehouse_id,
      coalesce(sum(remaining_quantity*unit_cost)/nullif(sum(remaining_quantity),0),0) avg_cost
    from public.erp_inventory_cost_layers
    where company_id=p_company_id and status in ('active','consumed') and remaining_quantity>0
      and item_type='product'
    group by item_id,warehouse_id
  ), changed as (
    update public.erp_warehouse_stock s set
      data=jsonb_set(
        jsonb_set(s.data,'{averageUnitCost}',to_jsonb(round(coalesce(c.avg_cost,0),6)),true),
        '{stockValue}',to_jsonb(round(public.erp_try_numeric(s.data->>'quantity',0)*coalesce(c.avg_cost,0),6)),true
      ),version=s.version+1,updated_at=now(),updated_by=auth.uid()
    from costs c where s.company_id=p_company_id and not s.is_deleted
      and coalesce(s.data->>'productId',s.data->>'itemId')=c.item_id
      and coalesce(s.data->>'warehouseId',s.data->>'warehouse_id')=c.warehouse_id
    returning 1
  ) select count(*) into v_updated from changed;

  update public.erp_warehouse_stock s set
    data=jsonb_set(jsonb_set(s.data,'{averageUnitCost}','0'::jsonb,true),'{stockValue}','0'::jsonb,true),
    version=s.version+1,updated_at=now(),updated_by=auth.uid()
  where s.company_id=p_company_id and not s.is_deleted
    and public.erp_try_numeric(s.data->>'quantity',0)<=0
    and (public.erp_try_numeric(s.data->>'averageUnitCost',0)<>0 or public.erp_try_numeric(s.data->>'stockValue',0)<>0);

  select coalesce(sum(remaining_quantity*unit_cost),0) into v_total
  from public.erp_inventory_cost_layers where company_id=p_company_id
    and status in ('active','consumed') and remaining_quantity>0;
  return jsonb_build_object('updatedStocks',v_updated,'inventoryValue',round(v_total,6),'calculatedAt',now());
end $$;

create or replace function public.erp_current_inventory_value(p_company_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
  select coalesce(sum(l.remaining_quantity*l.unit_cost),0)
  from public.erp_inventory_cost_layers l
  where l.company_id=p_company_id and l.status in ('active','consumed') and l.remaining_quantity>0
$$;


create or replace function public.erp_sync_stock_value_from_cost_layers()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_company uuid:=coalesce(new.company_id,old.company_id);
  v_item text:=coalesce(new.item_id,old.item_id);
  v_warehouse text:=coalesce(new.warehouse_id,old.warehouse_id);
  v_type text:=coalesce(new.item_type,old.item_type);
  v_avg numeric:=0;
begin
  if v_type<>'product' then return coalesce(new,old); end if;
  select coalesce(sum(remaining_quantity*unit_cost)/nullif(sum(remaining_quantity),0),0)
    into v_avg from public.erp_inventory_cost_layers
  where company_id=v_company and item_type='product' and item_id=v_item
    and warehouse_id=v_warehouse and status in ('active','consumed') and remaining_quantity>0;
  update public.erp_warehouse_stock s set
    data=jsonb_set(
      jsonb_set(s.data,'{averageUnitCost}',to_jsonb(round(v_avg,6)),true),
      '{stockValue}',to_jsonb(round(public.erp_try_numeric(s.data->>'quantity',0)*v_avg,6)),true
    ),version=s.version+1,updated_at=now(),updated_by=auth.uid()
  where s.company_id=v_company and not s.is_deleted
    and coalesce(s.data->>'productId',s.data->>'itemId')=v_item
    and coalesce(s.data->>'warehouseId',s.data->>'warehouse_id')=v_warehouse;
  return coalesce(new,old);
end $$;

drop trigger if exists erp_inventory_cost_layers_sync_stock_value on public.erp_inventory_cost_layers;
create trigger erp_inventory_cost_layers_sync_stock_value
after insert or update of remaining_quantity,unit_cost,status or delete
on public.erp_inventory_cost_layers for each row execute function public.erp_sync_stock_value_from_cost_layers();

-- One-time historical rebuild. Migrations run without an authenticated ERP user,
-- so execute the data rebuild directly instead of calling the permission-protected RPC.
with costs as (
  select company_id,item_id,warehouse_id,
    coalesce(sum(remaining_quantity*unit_cost)/nullif(sum(remaining_quantity),0),0) average_cost
  from public.erp_inventory_cost_layers
  where status in ('active','consumed') and remaining_quantity>0 and item_type='product'
  group by company_id,item_id,warehouse_id
)
update public.erp_warehouse_stock s set
  data=jsonb_set(jsonb_set(s.data,'{averageUnitCost}',to_jsonb(round(coalesce(c.average_cost,0),6)),true),
    '{stockValue}',to_jsonb(round(public.erp_try_numeric(s.data->>'quantity',0)*coalesce(c.average_cost,0),6)),true),
  version=s.version+1,updated_at=now()
from costs c where s.company_id=c.company_id and not s.is_deleted
  and coalesce(s.data->>'productId',s.data->>'itemId')=c.item_id
  and coalesce(s.data->>'warehouseId',s.data->>'warehouse_id')=c.warehouse_id;

update public.erp_warehouse_stock s set
  data=jsonb_set(jsonb_set(s.data,'{averageUnitCost}','0'::jsonb,true),'{stockValue}','0'::jsonb,true),
  version=s.version+1,updated_at=now()
where not s.is_deleted and public.erp_try_numeric(s.data->>'quantity',0)<=0
  and (public.erp_try_numeric(s.data->>'averageUnitCost',0)<>0 or public.erp_try_numeric(s.data->>'stockValue',0)<>0);

grant execute on function public.erp_workflow_partner_account(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_resolve_linked_cash_account(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_rebuild_live_inventory_values(uuid) to authenticated,service_role;
grant execute on function public.erp_current_inventory_value(uuid) to authenticated,service_role;

commit;
