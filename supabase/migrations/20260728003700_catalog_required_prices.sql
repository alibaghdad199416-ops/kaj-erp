-- Require explicit catalog cost and sale price while allowing zero.
-- Existing legacy rows are normalized first so future unrelated updates remain valid.
update public.erp_cars
set data = data || jsonb_build_object(
  'purchasePrice', coalesce(public.erp_try_numeric(coalesce(data->>'purchasePrice', data->>'costPrice'), null), 0),
  'costPrice', coalesce(public.erp_try_numeric(coalesce(data->>'purchasePrice', data->>'costPrice'), null), 0),
  'salePrice', coalesce(public.erp_try_numeric(data->>'salePrice', null), 0),
  'currency', upper(coalesce(nullif(btrim(data->>'currency'), ''), 'IQD')),
  'costCurrency', upper(coalesce(nullif(btrim(coalesce(data->>'costCurrency', data->>'cost_currency', data->>'currency')), ''), 'IQD')),
  'saleCurrency', upper(coalesce(nullif(btrim(coalesce(data->>'saleCurrency', data->>'sale_currency', data->>'currency')), ''), 'IQD'))
)
where not coalesce(is_deleted, false);

update public.erp_inventory
set data = data || jsonb_build_object(
  'purchasePrice', coalesce(public.erp_try_numeric(coalesce(data->>'purchasePrice', data->>'unitCost', data->>'costPrice'), null), 0),
  'unitCost', coalesce(public.erp_try_numeric(coalesce(data->>'unitCost', data->>'purchasePrice', data->>'costPrice'), null), 0),
  'salePrice', coalesce(public.erp_try_numeric(data->>'salePrice', null), 0),
  'currency', upper(coalesce(nullif(btrim(data->>'currency'), ''), 'IQD')),
  'costCurrency', upper(coalesce(nullif(btrim(coalesce(data->>'costCurrency', data->>'cost_currency', data->>'currency')), ''), 'IQD')),
  'saleCurrency', upper(coalesce(nullif(btrim(coalesce(data->>'saleCurrency', data->>'sale_currency', data->>'currency')), ''), 'IQD'))
)
where not coalesce(is_deleted, false);

create or replace function public.erp_validate_catalog_required_prices()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_cost numeric;
  v_sale numeric;
  v_currency text;
begin
  if new.is_deleted then return new; end if;

  v_currency := upper(btrim(coalesce(new.data->>'currency', '')));
  if v_currency not in ('IQD', 'USD') then
    raise exception 'يجب تحديد عملة صحيحة للسعر والكلفة';
  end if;

  if tg_table_name = 'erp_cars' then
    if not (new.data ? 'purchasePrice') or nullif(btrim(new.data->>'purchasePrice'), '') is null then
      raise exception 'كلفة السيارة مطلوبة ويمكن أن تكون صفراً';
    end if;
    v_cost := public.erp_try_numeric(new.data->>'purchasePrice', null);
  else
    if not (new.data ? 'unitCost') or nullif(btrim(new.data->>'unitCost'), '') is null then
      raise exception 'كلفة المنتج مطلوبة ويمكن أن تكون صفراً';
    end if;
    v_cost := public.erp_try_numeric(new.data->>'unitCost', null);
  end if;

  if not (new.data ? 'salePrice') or nullif(btrim(new.data->>'salePrice'), '') is null then
    raise exception 'سعر البيع مطلوب ويمكن أن يكون صفراً';
  end if;
  v_sale := public.erp_try_numeric(new.data->>'salePrice', null);

  if v_cost is null or v_cost < 0 then raise exception 'الكلفة يجب أن تكون رقماً غير سالب'; end if;
  if v_sale is null or v_sale < 0 then raise exception 'سعر البيع يجب أن يكون رقماً غير سالب'; end if;

  new.data := new.data || jsonb_build_object(
    'currency', v_currency,
    'costCurrency', v_currency,
    'saleCurrency', v_currency,
    'cost_currency', v_currency,
    'sale_currency', v_currency,
    'salePrice', v_sale
  );
  if tg_table_name = 'erp_cars' then
    new.data := new.data || jsonb_build_object('purchasePrice', v_cost, 'costPrice', v_cost);
  else
    new.data := new.data || jsonb_build_object('purchasePrice', v_cost, 'unitCost', v_cost, 'costPrice', v_cost);
  end if;
  return new;
end;
$$;

drop trigger if exists erp_cars_required_prices_trg on public.erp_cars;
create trigger erp_cars_required_prices_trg
before insert or update on public.erp_cars
for each row execute function public.erp_validate_catalog_required_prices();

drop trigger if exists erp_inventory_required_prices_trg on public.erp_inventory;
create trigger erp_inventory_required_prices_trg
before insert or update on public.erp_inventory
for each row execute function public.erp_validate_catalog_required_prices();
