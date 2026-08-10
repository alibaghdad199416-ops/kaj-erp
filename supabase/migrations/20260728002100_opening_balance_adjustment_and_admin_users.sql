begin;

-- Adjust a product's opening balance after creation without rewriting historical
-- purchase/sale movements. The delta is recorded as an auditable adjustment.
create or replace function public.erp_adjust_product_opening_balance(
  p_company_id uuid,
  p_product_id text,
  p_warehouse_id text,
  p_new_opening_quantity integer,
  p_user_name text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_stock public.erp_warehouse_stock%rowtype;
  v_current integer;
  v_delta integer;
  v_cost numeric;
begin
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  if p_new_opening_quantity < 0 then
    raise exception 'opening_quantity_invalid';
  end if;
  if not exists (
    select 1 from public.erp_inventory
    where company_id=p_company_id and id=p_product_id and not is_deleted
  ) then
    raise exception 'product_not_found';
  end if;

  v_stock := public.erp_inventory_ensure_stock(
    p_company_id,
    p_warehouse_id,
    p_product_id
  );
  v_current := coalesce((v_stock.data->>'quantity')::integer,0);
  v_delta := p_new_opening_quantity - v_current;
  if v_delta = 0 then return; end if;
  v_cost := coalesce((v_stock.data->>'averageUnitCost')::numeric,0);

  update public.erp_warehouse_stock
  set data=data||jsonb_build_object(
        'quantity',p_new_opening_quantity,
        'updatedAt',now(),
        'openingBalanceUpdatedBy',coalesce(nullif(btrim(p_user_name),''),auth.uid()::text)
      ),
      updated_at=now(),
      updated_by=auth.uid()
  where company_id=p_company_id and id=v_stock.id;

  perform public.erp_inventory_insert_movement(
    p_company_id,
    p_product_id,
    p_warehouse_id,
    'opening_adjustment',
    v_delta,
    v_cost,
    'product_opening_adjustment',
    p_product_id,
    'تعديل الرصيد الافتتاحي من '||v_current||' إلى '||p_new_opening_quantity
  );
  perform public.erp_inventory_refresh_product(p_company_id,p_product_id);
end $$;

grant execute on function public.erp_adjust_product_opening_balance(uuid,text,text,integer,text) to authenticated;

commit;
