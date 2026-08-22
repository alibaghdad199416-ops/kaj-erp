-- Quality Line ERP / KAJ ERP R99.6
-- Restore the canonical maintenance workflow engine as the direct owner of
-- invoice-draft creation and invoice approval. Preserve R57's explicit material
-- issue boundary instead of delegating these stages through the pre-R54 engine.
begin;

create or replace function public.erp_advance_cloud_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.approve']
  );
  select * into o
  from public.erp_maintenance_orders
  where id=p_order_id and company_id=p_company_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  if o.workflow_stage='order_draft' then
    update public.erp_maintenance_orders
    set workflow_stage='order_approved',status='approved',updated_at=v_now
    where id=o.id;
  elsif o.workflow_stage='order_approved' then
    update public.erp_maintenance_orders
    set workflow_stage='stock_issue_draft',stock_issue_number='PENDING',updated_at=v_now
    where id=o.id;
  elsif o.workflow_stage='stock_issue_draft' then
    if exists(
      select 1
      from public.erp_maintenance_parts
      where company_id=p_company_id and maintenance_order_id=p_order_id
        and not is_deleted and line_type<>'service'
    ) then
      raise exception 'maintenance_material_issue_action_required';
    end if;
    update public.erp_maintenance_orders
    set workflow_stage='stock_issue_approved',updated_at=v_now
    where id=o.id;
  elsif o.workflow_stage='stock_issue_approved' then
    update public.erp_maintenance_orders
    set workflow_stage=case
          when pricing_type='paid' then 'invoice_draft'
          else 'completed'
        end,
        status=case
          when pricing_type='paid' then status
          else 'completed'
        end,
        invoice_number=case
          when pricing_type='paid' then 'PENDING'
          else invoice_number
        end,
        updated_at=v_now
    where id=o.id;
  elsif o.workflow_stage='invoice_draft' then
    update public.erp_maintenance_orders
    set invoice_number=case
          when invoice_number is null or invoice_number='PENDING' then
            public.erp_next_document_number(
              p_company_id,'maintenance_invoice','MINV',o.maintenance_date
            )
          else invoice_number
        end,
        updated_at=v_now
    where id=o.id;
    perform public.erp_v736_post_maintenance_invoice(p_company_id,o.id);
    update public.erp_maintenance_orders
    set workflow_stage='invoice_approved',updated_at=v_now
    where id=o.id;
  else
    raise exception 'maintenance_no_next_stage';
  end if;
end;
$$;

-- The R99-scoped R37 wrapper is the supported browser mutation boundary.
revoke all on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid)
  to service_role;

notify pgrst,'reload schema';
commit;
