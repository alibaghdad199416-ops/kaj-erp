begin;

-- R49: forward-only CRM closure. UUIDs remain relational keys; this trigger only
-- owns the user-facing 7-character opportunity reference.
create or replace function public.erp_r49_assign_opportunity_business_reference()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_next integer;
  v_ref text;
begin
  if new.entity_type <> 'opportunities' or new.deleted_at is not null then
    return new;
  end if;
  if coalesce(new.payload->>'opportunityNumber','') ~ '^OPP[0-9]{4}$' then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('r49:opp:' || coalesce(new.company_id,'')));
  select coalesce(max(substring(payload->>'opportunityNumber' from 4 for 4)::integer),0)+1
    into v_next
  from public.erp_records
  where company_id=new.company_id and entity_type='opportunities' and deleted_at is null
    and coalesce(payload->>'opportunityNumber','') ~ '^OPP[0-9]{4}$';
  if v_next > 9999 then
    raise exception 'Opportunity business reference range exhausted for company %', new.company_id;
  end if;
  v_ref := 'OPP' || lpad(v_next::text,4,'0');
  new.payload := coalesce(new.payload,'{}'::jsonb) || jsonb_build_object('opportunityNumber',v_ref);
  return new;
end $$;

revoke all on function public.erp_r49_assign_opportunity_business_reference() from public,anon;
grant execute on function public.erp_r49_assign_opportunity_business_reference() to authenticated,service_role;

drop trigger if exists trg_r49_opportunity_business_reference on public.erp_records;
create trigger trg_r49_opportunity_business_reference
before insert or update of payload,deleted_at on public.erp_records
for each row execute function public.erp_r49_assign_opportunity_business_reference();

-- Normalize legacy opportunity references deterministically per tenant.
do $$
declare c record; rec record; n integer;
begin
  for c in select distinct company_id from public.erp_records where entity_type='opportunities' and deleted_at is null loop
    n:=0;
    for rec in select id from public.erp_records where company_id=c.company_id and entity_type='opportunities' and deleted_at is null order by created_at,id loop
      n:=n+1;
      update public.erp_records set payload=payload||jsonb_build_object('opportunityNumber','OPP'||lpad(n::text,4,'0')) where id=rec.id;
    end loop;
  end loop;
end $$;

create unique index if not exists erp_records_r49_opportunity_business_reference_uq
on public.erp_records(company_id,(payload->>'opportunityNumber'))
where entity_type='opportunities' and deleted_at is null;

notify pgrst,'reload schema';
commit;
