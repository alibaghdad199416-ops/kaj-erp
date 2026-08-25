begin;

-- R49 master-data business references. Internal UUID/text ids remain untouched;
-- only the existing user-facing carNumber/code fields are populated when they
-- are blank. Existing customer-defined references are preserved for backward
-- compatibility.
create or replace function public.erp_r49_assign_car_business_reference()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_next integer; v_ref text;
begin
  if new.is_deleted or coalesce(btrim(new.data->>'carNumber'),'')<>'' then return new; end if;
  perform pg_advisory_xact_lock(hashtext('r49:car:'||new.company_id::text));
  select coalesce(max(substring(data->>'carNumber' from 4 for 4)::integer),0)+1 into v_next
  from public.erp_cars
  where company_id=new.company_id and not is_deleted and coalesce(data->>'carNumber','')~'^CAR[0-9]{4}$';
  if v_next>9999 then raise exception 'Car business reference range exhausted for company %',new.company_id; end if;
  v_ref:='CAR'||lpad(v_next::text,4,'0');
  new.data:=coalesce(new.data,'{}'::jsonb)||jsonb_build_object('carNumber',v_ref,'car_number',v_ref);
  return new;
end $$;

drop trigger if exists trg_r49_car_business_reference on public.erp_cars;
create trigger trg_r49_car_business_reference
before insert or update of data,is_deleted on public.erp_cars
for each row execute function public.erp_r49_assign_car_business_reference();

create or replace function public.erp_r49_assign_inventory_business_reference()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_next integer; v_ref text;
begin
  if new.is_deleted or coalesce(btrim(new.data->>'code'),'')<>'' then return new; end if;
  perform pg_advisory_xact_lock(hashtext('r49:prd:'||new.company_id::text));
  select coalesce(max(substring(data->>'code' from 4 for 4)::integer),0)+1 into v_next
  from public.erp_inventory
  where company_id=new.company_id and not is_deleted and coalesce(data->>'code','')~'^PRD[0-9]{4}$';
  if v_next>9999 then raise exception 'Product business reference range exhausted for company %',new.company_id; end if;
  v_ref:='PRD'||lpad(v_next::text,4,'0');
  new.data:=coalesce(new.data,'{}'::jsonb)||jsonb_build_object('code',v_ref);
  return new;
end $$;

drop trigger if exists trg_r49_inventory_business_reference on public.erp_inventory;
create trigger trg_r49_inventory_business_reference
before insert or update of data,is_deleted on public.erp_inventory
for each row execute function public.erp_r49_assign_inventory_business_reference();

-- Backfill only records that currently have no user-facing reference. Existing
-- custom references are intentionally not rewritten.
do $$ declare c record; r record; n integer; begin
  for c in select distinct company_id from public.erp_cars where not is_deleted loop
    select coalesce(max(substring(data->>'carNumber' from 4 for 4)::integer),0) into n
    from public.erp_cars where company_id=c.company_id and not is_deleted and coalesce(data->>'carNumber','')~'^CAR[0-9]{4}$';
    for r in select id from public.erp_cars where company_id=c.company_id and not is_deleted and coalesce(btrim(data->>'carNumber'),'')='' order by created_at,id loop
      n:=n+1; if n>9999 then raise exception 'Car business reference range exhausted for company %',c.company_id; end if;
      update public.erp_cars set data=data||jsonb_build_object('carNumber','CAR'||lpad(n::text,4,'0'),'car_number','CAR'||lpad(n::text,4,'0')) where company_id=c.company_id and id=r.id;
    end loop;
  end loop;

  for c in select distinct company_id from public.erp_inventory where not is_deleted loop
    select coalesce(max(substring(data->>'code' from 4 for 4)::integer),0) into n
    from public.erp_inventory where company_id=c.company_id and not is_deleted and coalesce(data->>'code','')~'^PRD[0-9]{4}$';
    for r in select id from public.erp_inventory where company_id=c.company_id and not is_deleted and coalesce(btrim(data->>'code'),'')='' order by created_at,id loop
      n:=n+1; if n>9999 then raise exception 'Product business reference range exhausted for company %',c.company_id; end if;
      update public.erp_inventory set data=data||jsonb_build_object('code','PRD'||lpad(n::text,4,'0')) where company_id=c.company_id and id=r.id;
    end loop;
  end loop;
end $$;

create unique index if not exists erp_cars_r49_car_number_uq
on public.erp_cars(company_id,lower(btrim(data->>'carNumber')))
where not is_deleted and coalesce(data->>'carNumber','')~'^CAR[0-9]{4}$';

-- erp_inventory_code_uq already guards product codes; keep that established
-- uniqueness contract rather than creating a competing index.

revoke all on function public.erp_r49_assign_car_business_reference() from public,anon;
revoke all on function public.erp_r49_assign_inventory_business_reference() from public,anon;
grant execute on function public.erp_r49_assign_car_business_reference() to authenticated,service_role;
grant execute on function public.erp_r49_assign_inventory_business_reference() to authenticated,service_role;

notify pgrst,'reload schema';
commit;
