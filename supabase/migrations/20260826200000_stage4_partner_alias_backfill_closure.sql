begin;

-- Stage 4 forward-only data closure: normalize legacy partner identifier aliases
-- already stored before the Stage 4 trigger existed. The trigger is reused so
-- the same deterministic precedence rules apply to historical rows and future
-- writes. No Quality Line result participates in this closure.

update public.erp_customers
set data = data
where data is not null
  and (
    data->'national_id' is distinct from data->'nationalId'
    or data->'tax_number' is distinct from data->'taxNumber'
  );

update public.erp_suppliers
set data = data
where data is not null
  and (
    data->'national_id' is distinct from data->'nationalId'
    or data->'tax_number' is distinct from data->'taxNumber'
  );

-- Fail deterministically if historical data still contains an identifier
-- collision after normalization; silently choosing a survivor would lose data.
do $$
begin
  if exists (
    select 1
    from public.erp_customers
    where not is_deleted
      and coalesce(btrim(data->>'national_id'),'') <> ''
    group by company_id, lower(btrim(data->>'national_id'))
    having count(*) > 1
  ) then
    raise exception 'stage4_customer_national_id_collision_after_alias_normalization';
  end if;

  if exists (
    select 1
    from public.erp_suppliers
    where not is_deleted
      and coalesce(btrim(data->>'tax_number'),'') <> ''
    group by company_id, lower(btrim(data->>'tax_number'))
    having count(*) > 1
  ) then
    raise exception 'stage4_supplier_tax_number_collision_after_alias_normalization';
  end if;
end $$;

notify pgrst,'reload schema';
commit;
