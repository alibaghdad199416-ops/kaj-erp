begin;

-- Runtime compatibility closure: normalize the legacy purchaseCost/purchase_cost
-- aliases before the strict catalog-price validator rejects an otherwise valid
-- zero-cost vehicle. Canonical purchasePrice remains mandatory after this step.
create or replace function public.erp_validate_catalog_required_prices()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_cost numeric;
  v_sale numeric;
  v_currency text;
  v_cost_raw text;
begin
  if new.is_deleted then return new; end if;

  v_currency := upper(btrim(coalesce(new.data->>'currency', '')));
  if v_currency not in ('IQD', 'USD') then
    raise exception 'يجب تحديد عملة صحيحة للسعر والكلفة';
  end if;

  if tg_table_name = 'erp_cars' then
    v_cost_raw := coalesce(
      nullif(btrim(new.data->>'purchasePrice'), ''),
      nullif(btrim(new.data->>'costPrice'), ''),
      nullif(btrim(new.data->>'purchaseCost'), ''),
      nullif(btrim(new.data->>'purchase_cost'), ''),
      nullif(btrim(new.data->>'unitCost'), '')
    );
    if v_cost_raw is null then
      raise exception 'كلفة السيارة مطلوبة ويمكن أن تكون صفراً';
    end if;
    v_cost := public.erp_try_numeric(v_cost_raw, null);
  else
    v_cost_raw := coalesce(
      nullif(btrim(new.data->>'unitCost'), ''),
      nullif(btrim(new.data->>'purchasePrice'), ''),
      nullif(btrim(new.data->>'costPrice'), ''),
      nullif(btrim(new.data->>'purchaseCost'), ''),
      nullif(btrim(new.data->>'purchase_cost'), '')
    );
    if v_cost_raw is null then
      raise exception 'كلفة المنتج مطلوبة ويمكن أن تكون صفراً';
    end if;
    v_cost := public.erp_try_numeric(v_cost_raw, null);
  end if;

  if not (new.data ? 'salePrice') or nullif(btrim(new.data->>'salePrice'), '') is null then
    raise exception 'سعر البيع مطلوب ويمكن أن يكون صفراً';
  end if;
  v_sale := public.erp_try_numeric(new.data->>'salePrice', null);

  if v_cost is null or v_cost < 0 then raise exception 'الكلفة يجب أن تكون رقماً غير سالب'; end if;
  if v_sale is null or v_sale < 0 then raise exception 'سعر البيع يجب أن تكون رقماً غير سالب'; end if;

  new.data := new.data || jsonb_build_object(
    'currency', v_currency,
    'costCurrency', v_currency,
    'saleCurrency', v_currency,
    'cost_currency', v_currency,
    'sale_currency', v_currency,
    'salePrice', v_sale
  );

  if tg_table_name = 'erp_cars' then
    new.data := new.data || jsonb_build_object(
      'purchasePrice', v_cost,
      'costPrice', v_cost
    );
  else
    new.data := new.data || jsonb_build_object(
      'purchasePrice', v_cost,
      'unitCost', v_cost,
      'costPrice', v_cost
    );
  end if;

  return new;
end;
$$;

commit;
