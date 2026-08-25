-- Quality Line ERP R9: preserve FX precision end-to-end and enforce granular
-- write permissions at the database boundary for commercial/maintenance inputs.
begin;

-- Store user-entered exchange rates without truncating the 15-20 fractional
-- digits accepted by the application. Existing values convert losslessly.
alter table if exists public.erp_sales_orders_cloud
  alter column exchange_rate type numeric(38,20) using exchange_rate::numeric(38,20);
alter table if exists public.erp_purchase_orders_cloud
  alter column exchange_rate type numeric(38,20) using exchange_rate::numeric(38,20);
alter table if exists public.erp_payment_settlement_plans
  alter column exchange_rate type numeric(38,20) using exchange_rate::numeric(38,20);
alter table if exists public.erp_maintenance_orders
  alter column exchange_rate type numeric(38,20) using exchange_rate::numeric(38,20);
alter table if exists public.erp_maintenance_payments
  alter column exchange_rate type numeric(38,20) using exchange_rate::numeric(38,20);

create or replace function public.erp_r9_guard_input_fields()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company_id uuid;
  v_resource text:=coalesce(TG_ARGV[0],'');
  v_insert_permission text:=nullif(coalesce(TG_ARGV[1],''),'');
  v_update_permission text:=nullif(coalesce(TG_ARGV[2],''),'');
  v_base_permission text;
  v_new jsonb:=to_jsonb(new);
  v_old jsonb:=case when TG_OP='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_pair text;
  v_column text;
  v_field text;
  v_index integer;
  v_changed boolean;
begin
  -- Migration/service operations are trusted. End-user RPC calls retain the
  -- authenticated JWT while running SECURITY DEFINER and are checked below.
  if coalesce(current_setting('request.jwt.claim.role',true),'')='service_role' then
    return new;
  end if;

  v_company_id:=nullif(v_new->>'company_id','')::uuid;
  if v_company_id is null then
    raise exception 'field_permission_company_required' using errcode='22023';
  end if;

  v_base_permission:=case when TG_OP='INSERT' then v_insert_permission else v_update_permission end;
  if v_base_permission is not null
     and not public.erp_cloud_user_has_permission(v_company_id,v_base_permission) then
    raise exception 'permission_denied:%',v_base_permission using errcode='42501';
  end if;

  -- If granular restriction is not enabled, the helpers return true and this
  -- loop is backward compatible with all existing roles.
  if TG_NARGS > 3 then
    for v_index in 3..TG_NARGS-1 loop
      v_pair:=TG_ARGV[v_index];
      v_column:=split_part(v_pair,'=',1);
      v_field:=split_part(v_pair,'=',2);
      if v_column='' or v_field='' then continue; end if;

      if TG_OP='INSERT' then
        v_changed:=v_new ? v_column and jsonb_typeof(v_new->v_column) is distinct from 'null';
      else
        v_changed:=(v_old->v_column) is distinct from (v_new->v_column);
      end if;
      if not v_changed then continue; end if;

      if not public.erp_cloud_user_can_edit_field(v_company_id,v_resource,v_field,null) then
        raise exception 'field_permission_denied:%.%',v_resource,v_field using errcode='42501';
      end if;
    end loop;
  end if;
  return new;
end;
$$;

-- The commercial workflow tables are RPC-owned. Prevent direct authenticated
-- DML from bypassing order/delivery/invoice accounting rules.
revoke insert,update,delete on public.erp_sales_orders_cloud from authenticated;
revoke insert,update,delete on public.erp_sales_order_items_cloud from authenticated;
revoke insert,update,delete on public.erp_purchase_orders_cloud from authenticated;
revoke insert,update,delete on public.erp_purchase_order_items_cloud from authenticated;
revoke insert,update,delete on public.erp_maintenance_orders from authenticated;
revoke insert,update,delete on public.erp_maintenance_parts from authenticated;
revoke insert,update,delete on public.erp_maintenance_payments from authenticated;

drop trigger if exists trg_r9_sales_order_field_guard on public.erp_sales_orders_cloud;
create trigger trg_r9_sales_order_field_guard
before insert or update on public.erp_sales_orders_cloud
for each row execute function public.erp_r9_guard_input_fields(
  'sales','sales.create','sales.update',
  'customer_id=customerId','opportunity_id=opportunityId','currency=currencyCode',
  'exchange_rate=exchangeRate','discount=discount','notes=notes','effective_at=operationalDate'
);

drop trigger if exists trg_r9_sales_item_field_guard on public.erp_sales_order_items_cloud;
create trigger trg_r9_sales_item_field_guard
before insert or update on public.erp_sales_order_items_cloud
for each row execute function public.erp_r9_guard_input_fields(
  'sales','','sales.update','item_id=items','description=items',
  'quantity=itemQuantity','unit_price=itemPrice'
);

drop trigger if exists trg_r9_purchase_order_field_guard on public.erp_purchase_orders_cloud;
create trigger trg_r9_purchase_order_field_guard
before insert or update on public.erp_purchase_orders_cloud
for each row execute function public.erp_r9_guard_input_fields(
  'purchases','purchases.create','purchases.update',
  'supplier_id=supplierId','currency=currencyCode','exchange_rate=exchangeRate',
  'discount=discount','notes=notes','effective_at=operationalDate'
);

drop trigger if exists trg_r9_purchase_item_field_guard on public.erp_purchase_order_items_cloud;
create trigger trg_r9_purchase_item_field_guard
before insert or update on public.erp_purchase_order_items_cloud
for each row execute function public.erp_r9_guard_input_fields(
  'purchases','','purchases.update','item_id=items','description=items',
  'quantity=itemQuantity','unit_cost=itemCost'
);

drop trigger if exists trg_r9_maintenance_order_field_guard on public.erp_maintenance_orders;
create trigger trg_r9_maintenance_order_field_guard
before insert or update on public.erp_maintenance_orders
for each row execute function public.erp_r9_guard_input_fields(
  'maintenance','maintenance.create','maintenance.update',
  'car_id=carId','customer_id=customerId','warehouse_id=warehouseId',
  'currency_code=currencyCode','exchange_rate=exchangeRate',
  'maintenance_date=operationalDate','pricing_type=pricingType',
  'labor_cost=laborCost','sale_price=salePrice','notes=notes'
);

drop trigger if exists trg_r9_maintenance_part_field_guard on public.erp_maintenance_parts;
create trigger trg_r9_maintenance_part_field_guard
before insert or update on public.erp_maintenance_parts
for each row execute function public.erp_r9_guard_input_fields(
  'maintenance','','maintenance.update','product_id=items',
  'warehouse_id=itemWarehouse','quantity=itemQuantity','unit_cost=itemPrice'
);

drop trigger if exists trg_r9_maintenance_payment_field_guard on public.erp_maintenance_payments;
create trigger trg_r9_maintenance_payment_field_guard
before insert or update on public.erp_maintenance_payments
for each row execute function public.erp_r9_guard_input_fields(
  'maintenance','','maintenance.update','amount=payments',
  'currency_code=payments','exchange_rate=exchangeRate','payment_date=operationalDate','notes=notes'
);

revoke all on function public.erp_r9_guard_input_fields() from public,anon,authenticated;

commit;
