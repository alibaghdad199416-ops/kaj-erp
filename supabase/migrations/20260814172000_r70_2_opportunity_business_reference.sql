-- Quality Line ERP R70.2 — concise human Opportunity references.
begin;

create sequence if not exists public.erp_opportunity_business_reference_seq
  as bigint start with 1 increment by 1 minvalue 1 cache 20;

revoke all on sequence public.erp_opportunity_business_reference_seq
  from public,anon,authenticated;
grant usage,select on sequence public.erp_opportunity_business_reference_seq
  to service_role;

create or replace function public.erp_r70_assign_opportunity_business_reference()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reference text;
begin
  if new.entity_type<>'opportunities' then return new; end if;

  -- Existing records keep their established daily reference. New records use a
  -- short PostgreSQL-owned number instead of the old millisecond UI identifier.
  if tg_op='INSERT' and (
    nullif(btrim(new.payload->>'opportunityNumber'),'') is null
    or new.payload->>'opportunityNumber' ~ '^OPP-[0-9]{11,}$'
  ) then
    v_reference:='OPP-'||lpad(
      nextval('public.erp_opportunity_business_reference_seq')::text,7,'0'
    );
    new.payload:=jsonb_set(
      coalesce(new.payload,'{}'::jsonb),
      '{opportunityNumber}',to_jsonb(v_reference),true
    );
  end if;

  return new;
end $$;

revoke all on function public.erp_r70_assign_opportunity_business_reference()
  from public,anon,authenticated;

drop trigger if exists erp_r70_opportunity_business_reference
  on public.erp_records;
create trigger erp_r70_opportunity_business_reference
before insert on public.erp_records
for each row execute function public.erp_r70_assign_opportunity_business_reference();

-- Prevent ambiguous references within one company without rewriting any
-- historical business reference. Duplicate historical data is diagnosed first;
-- only create the index when the existing corpus is clean.
do $$
begin
  if not exists(
    select 1
    from public.erp_records r
    where r.entity_type='opportunities' and r.deleted_at is null
      and nullif(btrim(r.payload->>'opportunityNumber'),'') is not null
    group by r.company_id,lower(btrim(r.payload->>'opportunityNumber'))
    having count(*)>1
  ) then
    execute 'create unique index if not exists erp_records_opportunity_reference_uq '
      ||'on public.erp_records(company_id,lower(btrim(payload->>''opportunityNumber''))) '
      ||'where entity_type=''opportunities'' and deleted_at is null '
      ||'and nullif(btrim(payload->>''opportunityNumber''),'''') is not null';
  end if;
end $$;

notify pgrst,'reload schema';
commit;
