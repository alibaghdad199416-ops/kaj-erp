-- R55.1 forward-only correction: CRM Won begins when the linked sales order is
-- approved/confirmed. Delivery, invoicing, accounting, and payment remain
-- separate commercial boundaries.
begin;

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
      from public.erp_sales_orders_cloud orders
      where orders.company_id=v_company_id
        and orders.opportunity_id=new.record_id
        and not orders.is_deleted
        and lower(coalesce(orders.status,'')) in ('approved','confirmed')
    ) or exists(
      select 1
      from public.erp_records sale
      where sale.company_id=new.company_id
        and sale.entity_type='sales'
        and sale.deleted_at is null and not sale.is_deleted
        and coalesce(sale.payload->>'opportunityId',sale.payload->>'opportunity_id')=new.record_id
    ) or exists(
      select 1
      from public.erp_sales_orders_cloud orders
      join public.erp_commercial_workflow_documents evidence
        on evidence.company_id=orders.company_id
       and evidence.parent_id=orders.id
       and evidence.module='sales'
       and evidence.document_type in ('delivery','invoice')
       and not evidence.is_deleted
       and lower(coalesce(evidence.status,'')) in
           ('approved','delivered','paid','completed')
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

revoke all on function public.erp_r55_1_guard_opportunity_terminal_state()
  from public,anon,authenticated;
grant execute on function public.erp_r55_1_guard_opportunity_terminal_state()
  to service_role;

create or replace function public.erp_sync_opportunity_sales_lifecycle(
  p_company_id uuid,p_opportunity_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  o public.erp_sales_orders_cloud%rowtype;
  d public.erp_commercial_workflow_documents%rowtype;
  i public.erp_commercial_workflow_documents%rowtype;
  v_current jsonb:='{}'::jsonb;
  v_paid numeric:=0;
  v_remaining numeric:=0;
  v_status text:='pending';
  v_stage text:='new';
  v_probability numeric:=0;
  v_closed timestamptz;
  v_order_status text;
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is null then return; end if;
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then return; end if;

  select coalesce(payload,'{}'::jsonb) into v_current
  from public.erp_records
  where company_id=v_slug and entity_type='opportunities'
    and record_id=p_opportunity_id and deleted_at is null
  limit 1;
  if not found then return; end if;

  v_status:=lower(coalesce(nullif(v_current->>'status',''),'pending'));
  v_stage:=lower(coalesce(nullif(v_current->>'stage',''),'new'));
  v_probability:=greatest(0,least(100,public.erp_try_numeric(v_current->>'probability',0)));
  v_closed:=nullif(v_current->>'closedAt','')::timestamptz;

  -- Prefer the active linked order. If only a soft-deleted linked order remains,
  -- retain it as canonical cancellation evidence instead of treating it as no link.
  select * into o from public.erp_sales_orders_cloud
  where company_id=p_company_id and opportunity_id=p_opportunity_id
  order by (not is_deleted) desc,updated_at desc,created_at desc,id desc limit 1;

  if o.id is not null then
    v_order_status:=case
      when o.is_deleted then 'deleted'
      else lower(coalesce(o.status,''))
    end;
    select * into d from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales'
      and document_type='delivery' and not is_deleted
      and lower(coalesce(status,'')) in ('approved','delivered','completed')
    order by updated_at desc,created_at desc,id desc limit 1;
    select * into i from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales'
      and document_type='invoice' and not is_deleted
      and lower(coalesce(status,'')) in ('approved','paid','completed')
    order by updated_at desc,created_at desc,id desc limit 1;

    if v_order_status in ('cancelled','canceled','void','deleted') then
      v_status:='lost';
      v_stage:='lost';
      v_probability:=0;
      v_closed:=coalesce(o.updated_at,o.created_at,now());
    elsif v_order_status in ('approved','confirmed') or d.id is not null or i.id is not null then
      v_status:='won';
      v_stage:='won';
      v_probability:=100;
      v_closed:=coalesce(v_closed,o.updated_at,o.created_at,now());
      if i.id is not null then
        v_paid:=public.erp_try_numeric(i.payload->>'paidAmount',0);
        v_remaining:=greatest(0,public.erp_try_numeric(
          i.payload->>'remainingAmount',
          public.erp_try_numeric(i.payload->>'totalAmount',0)-v_paid
        ));
        if v_remaining<=0.001 then
          v_stage:='closed';
          v_closed:=coalesce(i.effective_at,i.updated_at,i.created_at,v_closed);
        end if;
      end if;
    else
      v_status:='pending';
      v_stage:='proposal';
      v_probability:=greatest(v_probability,50);
      v_closed:=null;
    end if;
  end if;

  update public.erp_records set payload=payload||jsonb_build_object(
    'status',v_status,'stage',v_stage,'probability',v_probability,'closedAt',v_closed,
    'salesOrderId',case when o.id is null then null else o.id::text end,
    'salesOrderNumber',o.order_number,'salesOrderStatus',
      case when o.id is null then null else v_order_status end,
    'deliveryId',case when d.id is null then null else d.id::text end,
    'deliveryNumber',d.document_number,'deliveryStatus',d.status,
    'invoiceId',case when i.id is null then null else i.id::text end,
    'invoiceNumber',i.document_number,'invoiceStatus',i.status,
    'invoiceCurrency',i.payload->>'currency','paidAmount',v_paid,'remainingAmount',v_remaining,
    'paymentStatus',case
      when i.id is null then 'not_invoiced'
      when v_remaining<=0.001 then 'paid'
      when v_paid>0 then 'partial'
      else 'unpaid' end,
    'workflowLinked',o.id is not null,'workflowCanOpen',o.id is not null and not o.is_deleted,
    'workflowCompleted',i.id is not null and v_remaining<=0.001,
    'opportunityStatusSource','canonical_sales_workflow','updatedAt',now()
  ),updated_at=now()
  where company_id=v_slug and entity_type='opportunities'
    and record_id=p_opportunity_id and deleted_at is null;
end
$$;

revoke all on function public.erp_sync_opportunity_sales_lifecycle(uuid,text)
  from public,anon;
grant execute on function public.erp_sync_opportunity_sales_lifecycle(uuid,text)
  to authenticated,service_role;

-- Re-project existing links after both the guard and lifecycle are corrected.
do $$ declare r record; begin
  for r in select distinct company_id,opportunity_id
    from public.erp_sales_orders_cloud
    where nullif(btrim(coalesce(opportunity_id,'')),'') is not null
  loop
    perform public.erp_sync_opportunity_sales_lifecycle(r.company_id,r.opportunity_id);
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
