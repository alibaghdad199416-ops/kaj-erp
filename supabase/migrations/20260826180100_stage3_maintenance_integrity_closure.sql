begin;

-- Stage 3 maintenance integrity closure.
-- Forward-only repair independent of Quality Line Base/Tail.

create or replace function public.erp_r49_guard_single_active_maintenance_invoice()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.module<>'maintenance' or new.document_type<>'invoice'
     or coalesce(new.is_deleted,false)
     or lower(coalesce(new.status,'')) in ('cancelled','canceled','deleted','void','reversed') then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.company_id::text||':maintenance-invoice:'||new.parent_id::text,0));
  if exists (select 1 from public.erp_commercial_workflow_documents d
    where d.company_id=new.company_id and d.module='maintenance' and d.document_type='invoice'
      and d.parent_id=new.parent_id and d.id is distinct from new.id and not d.is_deleted
      and lower(coalesce(d.status,'')) not in ('cancelled','canceled','deleted','void','reversed')) then
    raise exception 'active_maintenance_invoice_exists' using errcode='23505';
  end if;
  return new;
end;
$$;

drop trigger if exists erp_r49_single_active_maintenance_invoice_guard on public.erp_commercial_workflow_documents;
create trigger erp_r49_single_active_maintenance_invoice_guard
before insert or update of company_id,module,document_type,parent_id,status,is_deleted
on public.erp_commercial_workflow_documents for each row execute function public.erp_r49_guard_single_active_maintenance_invoice();

create or replace function public.erp_r49_validate_maintenance_invoice_state(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype;
begin
  perform public.erp_active_company_context(p_company_id);
  select * into o from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted for share;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.pricing_type<>'paid' or coalesce(o.sale_price,0)<=0 then raise exception 'paid_maintenance_invoice_required'; end if;
  if upper(coalesce(o.currency_code,'')) not in ('IQD','USD') then raise exception 'maintenance_currency_invalid'; end if;
  if o.customer_id is null then raise exception 'paid_maintenance_customer_required'; end if;
  if o.workflow_stage not in ('invoice_draft','invoice_approved','paid','completed') then raise exception 'maintenance_invoice_stage_invalid'; end if;
end;
$$;

create or replace function public.erp_v736_post_maintenance_invoice(p_company_id uuid,p_order_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  perform public.erp_r49_validate_maintenance_invoice_state(p_company_id,p_order_id);
  return public.erp_v736_post_maintenance_invoice_pre_r49_identity(p_company_id,p_order_id);
end;
$$;

create or replace function public.erp_advance_cloud_maintenance_workflow(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; p record; s public.erp_warehouse_stock%rowtype; v_now timestamptz:=now(); product_id text; warehouse_id text;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  select * into o from public.erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.workflow_stage='order_draft' then
    update public.erp_maintenance_orders set workflow_stage='order_approved',status='approved',updated_at=v_now where id=o.id;
  elsif o.workflow_stage='order_approved' then
    update public.erp_maintenance_orders set workflow_stage='stock_issue_draft',stock_issue_number='PENDING',updated_at=v_now where id=o.id;
  elsif o.workflow_stage='stock_issue_draft' then
    for p in select * from public.erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=o.id and not is_deleted and line_type<>'service' loop
      product_id:=coalesce(p.source_product_id,p.product_id::text); warehouse_id:=coalesce(p.source_warehouse_id,p.warehouse_id::text,o.source_warehouse_id,o.warehouse_id::text);
      if warehouse_id is null then raise exception 'maintenance_warehouse_required:%',p.product_name; end if;
      select * into s from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and coalesce(data->>'warehouseId',data->>'warehouse_id')=warehouse_id and coalesce(data->>'productId',data->>'product_id')=product_id for update;
      if not found or public.erp_try_numeric(s.data->>'quantity',0)-public.erp_try_numeric(s.data->>'reservedQuantity',0)<p.quantity then raise exception 'maintenance_insufficient_stock:%',p.product_name; end if;
      update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',public.erp_try_numeric(data->>'quantity',0)-p.quantity,'updatedAt',v_now),updated_at=v_now,updated_by=auth.uid() where id=s.id;
      perform public.erp_inventory_insert_movement(p_company_id,product_id,warehouse_id,'maintenance_out',-p.quantity,p.unit_cost,'maintenance_order',o.id::text,'صرف كمي للصيانة '||o.order_number);
    end loop;
    perform public.erp_phase3_refresh_maintenance_products(p_company_id,o.id);
    -- Preserve Stage 3's accounting boundary: physical stock issue and its
    -- expense/asset journal are committed together before approval advances.
    perform public.erp_phase3_post_maintenance_issue(p_company_id,o.id);
    update public.erp_maintenance_orders set workflow_stage='stock_issue_approved',stock_issue_number=case when stock_issue_number is null or stock_issue_number='PENDING' then public.erp_next_document_number(p_company_id,'maintenance_stock_issue','MIS',o.maintenance_date) else stock_issue_number end,car_cost_added=0,updated_at=v_now where id=o.id;
  elsif o.workflow_stage='stock_issue_approved' then
    update public.erp_maintenance_orders set workflow_stage=case when pricing_type='paid' then 'invoice_draft' else 'completed' end,status=case when pricing_type='paid' then status else 'completed' end,invoice_number=case when pricing_type='paid' then 'PENDING' else invoice_number end,updated_at=v_now where id=o.id;
  elsif o.workflow_stage='invoice_draft' then
    perform public.erp_r49_validate_maintenance_invoice_state(p_company_id,o.id);
    update public.erp_maintenance_orders set invoice_number=case when invoice_number is null or invoice_number='PENDING' then public.erp_next_document_number(p_company_id,'maintenance_invoice','MINV',o.maintenance_date) else invoice_number end,updated_at=v_now where id=o.id;
    perform public.erp_v736_post_maintenance_invoice(p_company_id,o.id);
    update public.erp_maintenance_orders set workflow_stage='invoice_approved',updated_at=v_now where id=o.id;
  else
    raise exception 'maintenance_no_next_stage';
  end if;
end;
$$;

revoke all on function public.erp_r49_guard_single_active_maintenance_invoice() from public,anon;
revoke all on function public.erp_r49_validate_maintenance_invoice_state(uuid,uuid) from public,anon;
grant execute on function public.erp_r49_guard_single_active_maintenance_invoice() to authenticated,service_role;
grant execute on function public.erp_r49_validate_maintenance_invoice_state(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;