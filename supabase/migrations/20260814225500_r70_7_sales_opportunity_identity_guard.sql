-- Quality Line ERP R70.7 — canonical Opportunity <-> Sales identity guard.
-- Forward-only. A linked Sales Order must not diverge from the Opportunity's
-- customer/currency identity. Legacy historical mismatches are not silently
-- rewritten; unchanged legacy identity may still be cancelled/reversed safely,
-- while any create/re-link/reactivation or identity mutation must be exact.
begin;

create or replace function public.erp_validate_sales_order_opportunity_link()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_payload jsonb;
  v_opportunity_customer text;
  v_opportunity_currency text;
  v_same_historical_link boolean:=false;
  v_cancel_restore boolean:=false;
  v_reactivates_cancelled boolean:=false;
  v_creates_or_relinks boolean:=false;
  v_customer_changed boolean:=true;
  v_currency_changed boolean:=true;
begin
  if nullif(btrim(coalesce(new.opportunity_id,'')),'') is null then
    return new;
  end if;

  select slug into v_slug
  from public.companies
  where id=new.company_id and is_active;
  if v_slug is null then
    raise exception 'company_not_found' using errcode='23503';
  end if;

  select payload into v_payload
  from public.erp_records
  where company_id=v_slug
    and entity_type='opportunities'
    and record_id=new.opportunity_id
    and not is_deleted
    and deleted_at is null
  limit 1;

  if v_payload is null then
    raise exception 'opportunity_not_found' using errcode='23503';
  end if;

  if tg_op='UPDATE' then
    v_same_historical_link :=
      old.company_id is not distinct from new.company_id
      and old.opportunity_id is not distinct from new.opportunity_id;
    v_customer_changed := old.customer_id is distinct from new.customer_id;
    v_currency_changed := upper(coalesce(old.currency,''))
      is distinct from upper(coalesce(new.currency,''));

    -- R61-R67 cancellation may temporarily soft-delete the exact linked row and
    -- restore it as Cancelled after CRM has already projected Opportunity=Lost.
    -- Preserve that same historical row without treating it as a new conversion.
    v_cancel_restore :=
      v_same_historical_link
      and coalesce(old.is_deleted,false)
      and not coalesce(new.is_deleted,false)
      and lower(coalesce(new.status,'')) in ('cancelled','canceled','void');

    -- Reactivating a cancelled/void historical order is a new active commercial
    -- lifecycle boundary and must obey the same Lost + identity guards as create.
    v_reactivates_cancelled :=
      v_same_historical_link
      and not coalesce(new.is_deleted,false)
      and lower(coalesce(old.status,'')) in ('cancelled','canceled','void')
      and lower(coalesce(new.status,'')) not in ('cancelled','canceled','void');
  end if;

  v_creates_or_relinks :=
    tg_op='INSERT'
    or not v_same_historical_link
    or v_reactivates_cancelled
    or (
      tg_op='UPDATE'
      and coalesce(old.is_deleted,false)
      and not coalesce(new.is_deleted,false)
      and not v_cancel_restore
    );

  if lower(coalesce(v_payload->>'status','pending'))='lost'
     and v_creates_or_relinks then
    raise exception 'opportunity_is_lost' using errcode='P0001';
  end if;

  v_opportunity_customer := nullif(btrim(coalesce(v_payload->>'customerId','')),'');
  v_opportunity_currency := upper(nullif(btrim(coalesce(v_payload->>'currency','')),''));

  if v_opportunity_customer is null then
    raise exception 'opportunity_customer_required' using errcode='22023';
  end if;
  if v_opportunity_currency not in ('USD','IQD') then
    raise exception 'opportunity_currency_invalid' using errcode='22023';
  end if;

  -- Existing legacy mismatches are not rewritten by a migration. Allow an
  -- unchanged historical identity to reach governed Cancel/Reverse, but never
  -- allow a browser/internal mutation to create a new mismatch or reactivate a
  -- mismatched lifecycle. Moving a legacy row TOWARD the Opportunity identity is
  -- allowed because the final NEW values then satisfy these guards.
  if new.customer_id is distinct from v_opportunity_customer
     and (v_creates_or_relinks or v_customer_changed) then
    raise exception 'opportunity_customer_mismatch' using errcode='23514';
  end if;

  if upper(coalesce(new.currency,'')) is distinct from v_opportunity_currency
     and (v_creates_or_relinks or v_currency_changed) then
    raise exception 'opportunity_currency_mismatch' using errcode='23514';
  end if;

  return new;
end;
$$;

revoke all on function public.erp_validate_sales_order_opportunity_link()
  from public,anon,authenticated;
grant execute on function public.erp_validate_sales_order_opportunity_link()
  to service_role;

drop trigger if exists erp_validate_sales_order_opportunity_link_trg
on public.erp_sales_orders_cloud;
create trigger erp_validate_sales_order_opportunity_link_trg
before insert or update of
  company_id,customer_id,opportunity_id,is_deleted,status,currency
on public.erp_sales_orders_cloud
for each row
when (not coalesce(new.is_deleted,false))
execute function public.erp_validate_sales_order_opportunity_link();

notify pgrst,'reload schema';
commit;
