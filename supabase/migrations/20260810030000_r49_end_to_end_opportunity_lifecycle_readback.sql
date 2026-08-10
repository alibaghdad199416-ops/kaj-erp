begin;

-- R49 end-to-end closure: the opportunity projection must describe the same
-- canonical commercial workflow that the sales module shows. This function is
-- already the trigger target for order/delivery/invoice changes, so redefining
-- it forward-only fixes every caller without adding a parallel state machine.
create or replace function public.erp_sync_opportunity_sales_lifecycle(
  p_company_id uuid,p_opportunity_id text
) returns void language plpgsql security definer set search_path=public as $$
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

  select * into o from public.erp_sales_orders_cloud
  where company_id=p_company_id and opportunity_id=p_opportunity_id and not is_deleted
  order by updated_at desc,created_at desc,id desc limit 1;

  if o.id is not null then
    v_order_status:=lower(coalesce(o.status,''));
    select * into d from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales' and document_type='delivery'
      and not is_deleted and lower(coalesce(status,'')) in ('approved','delivered','completed')
    order by updated_at desc,created_at desc,id desc limit 1;
    select * into i from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales' and document_type='invoice'
      and not is_deleted and lower(coalesce(status,'')) in ('approved','paid','completed')
    order by updated_at desc,created_at desc,id desc limit 1;

    if v_order_status in ('cancelled','canceled','void','deleted') then
      v_status:='lost';
      v_stage:='lost';
      v_probability:=0;
      v_closed:=coalesce(o.updated_at,o.created_at,now());
    elsif i.id is not null then
      v_paid:=public.erp_try_numeric(i.payload->>'paidAmount',0);
      v_remaining:=greatest(0,public.erp_try_numeric(
        i.payload->>'remainingAmount',
        public.erp_try_numeric(i.payload->>'totalAmount',0)-v_paid
      ));
      v_status:='won';
      v_probability:=100;
      if v_remaining<=0.001 then
        v_stage:='closed';
      else
        v_stage:='won';
      end if;
      v_closed:=coalesce(i.effective_at,i.updated_at,i.created_at,now());
    elsif d.id is not null then
      v_status:='pending';
      v_stage:='negotiation';
      v_probability:=greatest(v_probability,80);
      v_closed:=null;
    elsif v_order_status in ('approved','confirmed') then
      v_status:='pending';
      v_stage:='negotiation';
      v_probability:=greatest(v_probability,70);
      v_closed:=null;
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
    'salesOrderNumber',o.order_number,'salesOrderStatus',o.status,
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
    'workflowLinked',o.id is not null,'workflowCanOpen',o.id is not null,
    'workflowCompleted',i.id is not null and v_remaining<=0.001,
    'opportunityStatusSource','canonical_sales_workflow','updatedAt',now()
  ),updated_at=now()
  where company_id=v_slug and entity_type='opportunities'
    and record_id=p_opportunity_id and deleted_at is null;
end $$;

revoke all on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) from public,anon;
grant execute on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) to authenticated,service_role;

-- Re-project every active link once so existing opportunities immediately gain
-- the corrected stage/probability/payment projection when this migration lands.
do $$ declare r record; begin
  for r in select distinct company_id,opportunity_id
    from public.erp_sales_orders_cloud
    where not is_deleted and nullif(btrim(coalesce(opportunity_id,'')),'') is not null
  loop
    perform public.erp_sync_opportunity_sales_lifecycle(r.company_id,r.opportunity_id);
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
