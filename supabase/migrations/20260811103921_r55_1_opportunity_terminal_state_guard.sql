-- R55.1 forward-only closure: terminal opportunity state is owned by the
-- canonical loss/sales workflows, never by an ordinary browser save.
begin;

-- Preserve the fully hardened R49 implementation as an internal delegate, then
-- keep the public signature stable while correcting canonical Lost read-back.
alter function public.erp_r49_opportunity_command(text,jsonb)
  rename to erp_r49_opportunity_command_pre_r55_1;
revoke all on function public.erp_r49_opportunity_command_pre_r55_1(text,jsonb)
  from public,anon,authenticated;

create or replace function public.erp_r49_opportunity_command(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_company uuid;
  v_slug text;
  v_admin boolean;
  v_id text;
begin
  v_result:=public.erp_r49_opportunity_command_pre_r55_1(
    p_action,coalesce(p_payload,'{}'::jsonb)
  );
  if p_action<>'mark_lost' then return v_result; end if;

  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_company is null then
    raise exception 'membership_not_found' using errcode='42501';
  end if;
  v_id:=nullif(btrim(coalesce(p_payload->>'id','')),'');
  select r.payload||jsonb_build_object(
           'updatedAt',r.updated_at,'_cloudUpdatedAt',r.updated_at
         ) into v_result
  from public.erp_records r
  where r.company_id=v_slug and r.entity_type='opportunities'
    and r.record_id=v_id and r.deleted_at is null
  limit 1;
  if v_result is null then
    raise exception 'opportunity_not_found' using errcode='P0002';
  end if;
  return public.erp_r9_filter_readable_json(
    v_company,'opportunities',v_result
  );
end
$$;
revoke all on function public.erp_r49_opportunity_command(text,jsonb)
  from public,anon;
grant execute on function public.erp_r49_opportunity_command(text,jsonb)
  to authenticated,service_role;

create or replace function public.erp_r55_1_guard_opportunity_terminal_state()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_old_stage text:='';
  v_old_status text:='';
  v_new_stage text:=lower(coalesce(new.payload->>'stage',''));
  v_new_status text:=lower(coalesce(new.payload->>'status',''));
  v_company_id uuid;
  v_has_canonical_win boolean:=false;
begin
  if new.entity_type<>'opportunities' or new.is_deleted or new.deleted_at is not null then
    return new;
  end if;
  if tg_op='UPDATE' then
    v_old_stage:=lower(coalesce(old.payload->>'stage',''));
    v_old_status:=lower(coalesce(old.payload->>'status',''));
  end if;

  -- The canonical mark_lost command historically changed status only. Make its
  -- projection atomic and consistent, while rejecting a browser payload that
  -- merely writes stage=lost and leaves the opportunity pending.
  if v_new_stage='lost' and v_new_status<>'lost' then
    raise exception 'opportunity_lost_requires_mark_lost' using errcode='22023';
  end if;
  if v_new_status='lost' and v_old_status<>'lost' then
    new.payload:=new.payload||jsonb_build_object(
      'stage','lost','status','lost','probability',0,
      'closedAt',coalesce(new.payload->'closedAt',to_jsonb(clock_timestamp()))
    );
    v_new_stage:='lost';
  end if;

  if (v_new_stage='won' and v_old_stage<>'won')
     or (v_new_status='won' and v_old_status<>'won') then
    select c.id into v_company_id
    from public.companies c
    where c.slug=new.company_id and c.is_active;

    v_has_canonical_win:=exists(
      select 1
      from public.erp_records sale
      where sale.company_id=new.company_id
        and sale.entity_type='sales'
        and sale.deleted_at is null and not sale.is_deleted
        and coalesce(sale.payload->>'opportunityId',sale.payload->>'opportunity_id')=new.record_id
    ) or exists(
      select 1
      from public.erp_sales_orders_cloud orders
      join public.erp_commercial_workflow_documents invoice
        on invoice.company_id=orders.company_id
       and invoice.parent_id=orders.id
       and invoice.module='sales'
       and invoice.document_type='invoice'
       and not invoice.is_deleted
       and lower(coalesce(invoice.status,'')) in ('approved','paid','completed')
      where orders.company_id=v_company_id
        and orders.opportunity_id=new.record_id
        and not orders.is_deleted
    );

    if not v_has_canonical_win then
      raise exception 'opportunity_won_requires_canonical_sales_workflow'
        using errcode='42501';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists erp_r55_1_opportunity_terminal_state_trg on public.erp_records;
create trigger erp_r55_1_opportunity_terminal_state_trg
before insert or update of payload,is_deleted,deleted_at on public.erp_records
for each row execute function public.erp_r55_1_guard_opportunity_terminal_state();

revoke all on function public.erp_r55_1_guard_opportunity_terminal_state()
  from public,anon,authenticated;
grant execute on function public.erp_r55_1_guard_opportunity_terminal_state()
  to service_role;

notify pgrst,'reload schema';
commit;
