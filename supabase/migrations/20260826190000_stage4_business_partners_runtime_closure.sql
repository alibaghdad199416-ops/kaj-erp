begin;

-- Stage 4: Business Partners runtime closure.
-- Forward-only hardening; independent of Quality Line Base/Tail.
-- The Flutter repositories write normalized master tables directly, so RLS
-- must enforce the same granular CRUD permissions as the UI.

do $$
declare t text;
begin
  foreach t in array array['erp_customers','erp_suppliers'] loop
    execute format('drop policy if exists %I_select on public.%I',t,t);
    execute format('drop policy if exists %I_insert on public.%I',t,t);
    execute format('drop policy if exists %I_update on public.%I',t,t);
    execute format('drop policy if exists %I_delete on public.%I',t,t);

    execute format('create policy %I_select on public.%I for select to authenticated using (public.is_active_company_member(company_id) and (public.is_company_admin(company_id) or public.erp_cloud_user_has_permission(company_id,case when %L=''erp_customers'' then ''customers.view'' else ''suppliers.view'' end)))',t,t,t);
    execute format('create policy %I_insert on public.%I for insert to authenticated with check (public.is_company_admin(company_id) or (public.is_active_company_member(company_id) and public.erp_cloud_user_has_permission(company_id,case when %L=''erp_customers'' then ''customers.create'' else ''suppliers.create'' end) and created_by=auth.uid() and updated_by=auth.uid()))',t,t,t);
    execute format('create policy %I_update on public.%I for update to authenticated using (public.is_company_admin(company_id) or (public.is_active_company_member(company_id) and public.erp_cloud_user_has_permission(company_id,case when %L=''erp_customers'' then ''customers.update'' else ''suppliers.update'' end))) with check (public.is_company_admin(company_id) or (public.is_active_company_member(company_id) and public.erp_cloud_user_has_permission(company_id,case when %L=''erp_customers'' then ''customers.update'' else ''suppliers.update'' end) and updated_by=auth.uid()))',t,t,t,t);
    execute format('create policy %I_delete on public.%I for delete to authenticated using (public.is_company_admin(company_id) or (public.is_active_company_member(company_id) and public.erp_cloud_user_has_permission(company_id,case when %L=''erp_customers'' then ''customers.delete'' else ''suppliers.delete'' end)))',t,t,t);
  end loop;
end $$;

-- Backend uniqueness for identifiers that must not collide inside a tenant.
-- Empty identifiers are ignored; soft-deleted rows release the identifier.
create unique index if not exists erp_customers_company_national_id_uq
  on public.erp_customers(company_id, lower(btrim(coalesce(data->>'national_id',data->>'nationalId'))))
  where not is_deleted and coalesce(btrim(coalesce(data->>'national_id',data->>'nationalId')),'') <> '';

create unique index if not exists erp_suppliers_company_tax_number_uq
  on public.erp_suppliers(company_id, lower(btrim(coalesce(data->>'tax_number',data->>'taxNumber'))))
  where not is_deleted and coalesce(btrim(coalesce(data->>'tax_number',data->>'taxNumber')),'') <> '';

-- Keep master JSON aliases deterministic for the fields used by Stage 4 cards,
-- so national IDs/tax numbers cannot silently diverge between old/new clients.
create or replace function public.erp_stage4_partner_alias_sync()
returns trigger language plpgsql security definer set search_path=public as $$
declare old_data jsonb:=case when tg_op='INSERT' then null else old.data end; v jsonb;
begin
  new.data:=coalesce(new.data,'{}'::jsonb);
  v:=public.erp_pick_changed_json_alias(new.data,old_data,array['national_id','nationalId']);
  new.data:=new.data||jsonb_build_object('national_id',v,'nationalId',v);
  v:=public.erp_pick_changed_json_alias(new.data,old_data,array['tax_number','taxNumber']);
  new.data:=new.data||jsonb_build_object('tax_number',v,'taxNumber',v);
  return new;
end;
$$;

drop trigger if exists erp_stage4_customer_supplier_alias_sync on public.erp_customers;
create trigger erp_stage4_customer_supplier_alias_sync
before insert or update of data on public.erp_customers for each row
execute function public.erp_stage4_partner_alias_sync();

drop trigger if exists erp_stage4_supplier_alias_sync on public.erp_suppliers;
create trigger erp_stage4_supplier_alias_sync
before insert or update of data on public.erp_suppliers for each row
execute function public.erp_stage4_partner_alias_sync();

revoke all on function public.erp_stage4_partner_alias_sync() from public,anon;
grant execute on function public.erp_stage4_partner_alias_sync() to service_role;

notify pgrst,'reload schema';
commit;
