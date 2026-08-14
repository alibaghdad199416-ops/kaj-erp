-- Quality Line ERP R70.8 — bidirectional Opportunity relationship integrity.
-- Once operational Sales/Maintenance history exists, CRM cannot silently change
-- the identity those documents were created against or delete the Opportunity
-- while a non-deleted linked lifecycle remains. Unchanged legacy mismatches are
-- tolerated so cancellation/reversal can still complete; new divergence is not.
begin;

create or replace function public.erp_r70_guard_opportunity_linked_identity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company_id uuid;
  v_old_customer text:=nullif(btrim(coalesce(old.payload->>'customerId','')),'');
  v_new_customer text:=nullif(btrim(coalesce(new.payload->>'customerId','')),'');
  v_old_currency text:=upper(nullif(btrim(coalesce(old.payload->>'currency','')),''));
  v_new_currency text:=upper(nullif(btrim(coalesce(new.payload->>'currency','')),''));
  v_old_car text:=nullif(btrim(coalesce(old.payload->>'carId','')),'');
  v_new_car text:=nullif(btrim(coalesce(new.payload->>'carId','')),'');
  v_has_sales boolean:=false;
  v_has_maintenance boolean:=false;
begin
  if tg_op<>'UPDATE'
     or new.entity_type<>'opportunities'
     or old.entity_type<>'opportunities' then
    return new;
  end if;

  select c.id into v_company_id
  from public.companies c
  where c.slug=new.company_id and c.is_active;
  if v_company_id is null then
    raise exception 'company_not_found' using errcode='23503';
  end if;

  select exists(
    select 1
    from public.erp_sales_orders_cloud o
    where o.company_id=v_company_id
      and o.opportunity_id=new.record_id
      and not o.is_deleted
  ) into v_has_sales;

  select exists(
    select 1
    from public.erp_maintenance_orders m
    where m.company_id=v_company_id
      and m.opportunity_id=new.record_id
      and not m.is_deleted
  ) into v_has_maintenance;

  if (coalesce(new.is_deleted,false) or new.deleted_at is not null) then
    if v_has_sales then
      raise exception 'opportunity_has_sales_history' using errcode='P0001';
    end if;
    if v_has_maintenance then
      raise exception 'opportunity_has_maintenance_history' using errcode='P0001';
    end if;
    return new;
  end if;

  -- Enforce only when CRM attempts to mutate an identity field. This preserves
  -- the ability to synchronize/cancel old mismatched history without making the
  -- records impossible to unwind, while allowing a corrective edit TOWARD the
  -- canonical linked identity.
  if v_has_sales and v_old_customer is distinct from v_new_customer then
    if exists(
      select 1
      from public.erp_sales_orders_cloud o
      where o.company_id=v_company_id
        and o.opportunity_id=new.record_id
        and not o.is_deleted
        and o.customer_id is distinct from v_new_customer
    ) then
      raise exception 'opportunity_sales_customer_locked' using errcode='23514';
    end if;
  end if;

  if v_has_sales and v_old_currency is distinct from v_new_currency then
    if exists(
      select 1
      from public.erp_sales_orders_cloud o
      where o.company_id=v_company_id
        and o.opportunity_id=new.record_id
        and not o.is_deleted
        and upper(coalesce(o.currency,'')) is distinct from v_new_currency
    ) then
      raise exception 'opportunity_sales_currency_locked' using errcode='23514';
    end if;
  end if;

  if v_has_maintenance and v_old_customer is distinct from v_new_customer then
    if exists(
      select 1
      from public.erp_maintenance_orders m
      where m.company_id=v_company_id
        and m.opportunity_id=new.record_id
        and not m.is_deleted
        and m.customer_id is not null
        and m.customer_id::text is distinct from v_new_customer
    ) then
      raise exception 'opportunity_maintenance_customer_locked' using errcode='23514';
    end if;
  end if;

  if v_has_maintenance and v_old_car is distinct from v_new_car then
    if exists(
      select 1
      from public.erp_maintenance_orders m
      where m.company_id=v_company_id
        and m.opportunity_id=new.record_id
        and not m.is_deleted
        and nullif(btrim(coalesce(m.source_car_id,'')),'') is distinct from v_new_car
    ) then
      raise exception 'opportunity_maintenance_vehicle_locked' using errcode='23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.erp_r70_guard_opportunity_linked_identity()
  from public,anon,authenticated;
grant execute on function public.erp_r70_guard_opportunity_linked_identity()
  to service_role;

drop trigger if exists erp_r70_opportunity_linked_identity_trg on public.erp_records;
create trigger erp_r70_opportunity_linked_identity_trg
before update of payload,is_deleted,deleted_at on public.erp_records
for each row
when (new.entity_type='opportunities')
execute function public.erp_r70_guard_opportunity_linked_identity();

notify pgrst,'reload schema';
commit;
