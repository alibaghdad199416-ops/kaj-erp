-- Quality Line ERP R70.6 — harden the Lost Opportunity Sales guard.
-- Existing linked cancellation must remain legal, but a cancelled/void Sales
-- lifecycle must not be silently reactivated while the Opportunity is Lost.
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
  v_same_historical_link boolean:=false;
  v_cancel_restore boolean:=false;
  v_reactivates_cancelled boolean:=false;
  v_creates_or_relinks boolean:=false;
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

    -- Commercial cancellation can temporarily soft-delete the exact existing
    -- order and then restore that same row as Cancelled after CRM has already
    -- projected the Opportunity to Lost. This restore is not a new conversion.
    v_cancel_restore :=
      v_same_historical_link
      and coalesce(old.is_deleted,false)
      and not coalesce(new.is_deleted,false)
      and lower(coalesce(new.status,'')) in ('cancelled','canceled','void');

    -- The inverse transition is materially different: bringing a cancelled or
    -- void historical order back to an active status is a reactivation and must
    -- obey the same Lost guard as a new/re-linked Sales order.
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
  if v_opportunity_customer is not null
     and v_opportunity_customer is distinct from new.customer_id then
    raise exception 'opportunity_customer_mismatch' using errcode='23514';
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
before insert or update of company_id,customer_id,opportunity_id,is_deleted,status
on public.erp_sales_orders_cloud
for each row
when (not coalesce(new.is_deleted,false))
execute function public.erp_validate_sales_order_opportunity_link();

notify pgrst,'reload schema';
commit;
