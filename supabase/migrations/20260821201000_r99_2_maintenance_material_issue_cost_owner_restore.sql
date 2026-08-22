-- Quality Line ERP / KAJ ERP R99.2
-- Restore the canonical maintenance material-issue executor as the direct
-- owner of FIFO consumption and inventory-cost accounting. R88 replaced this
-- function with a permission-only wrapper, leaving the proven R87 body behind
-- the pre_r88 compatibility name. Keep the R88 action guard while restoring the
-- accounting body under the canonical function used by R90 approval.
begin;

create or replace function public.erp_r57_execute_maintenance_material_issue(
  p_company_id uuid,p_order_id uuid,p_issue_id uuid,p_part_id uuid,
  p_warehouse_id text,p_quantity numeric,p_effective_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  mp public.erp_maintenance_parts%rowtype;
  ws public.erp_warehouse_stock%rowtype;
  w record;
  l record;
  v_product text;
  v_issued numeric;
  v_remaining numeric;
  v_needed numeric;
  v_take numeric;
  v_cost numeric:=0;
  v_existing public.erp_maintenance_material_issues%rowtype;
  v_cost_currency text;
  v_accounts jsonb;
  v_cost_lines jsonb;
  v_cost_journal text;
  v_effective timestamptz:=coalesce(p_effective_at,now());
begin
  perform public.erp_r88_require_restricted_action(
    p_company_id,'maintenance','material_issue.approve'
  );
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.approve','maintenance.update']
  );
  if p_issue_id is null then raise exception 'maintenance_issue_id_required'; end if;
  if coalesce(p_quantity,0)<=0 then
    raise exception 'maintenance_issue_quantity_must_be_positive';
  end if;
  if nullif(btrim(coalesce(p_warehouse_id,'')),'') is null then
    raise exception 'maintenance_issue_warehouse_required';
  end if;

  select * into v_existing
  from public.erp_maintenance_material_issues
  where company_id=p_company_id and id=p_issue_id;
  if found then
    select * into l
    from public.erp_maintenance_material_issue_lines
    where company_id=p_company_id and issue_id=p_issue_id;
    if v_existing.status='executed'
       and l.maintenance_order_id=p_order_id
       and l.maintenance_part_id=p_part_id
       and l.warehouse_id=p_warehouse_id
       and l.quantity=p_quantity then
      return jsonb_build_object(
        'issueId',p_issue_id,'idempotent',true,'status','executed',
        'journalEntryId',v_existing.journal_entry_id
      );
    end if;
    raise exception 'maintenance_issue_id_conflict';
  end if;

  select * into o
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.workflow_stage<>'stock_issue_draft' then
    raise exception 'maintenance_issue_stage_invalid:%',o.workflow_stage;
  end if;

  select * into mp
  from public.erp_maintenance_parts
  where company_id=p_company_id and id=p_part_id
    and maintenance_order_id=p_order_id
    and not is_deleted and line_type<>'service'
  for update;
  if not found then raise exception 'maintenance_part_not_found'; end if;
  v_product:=coalesce(mp.source_product_id,mp.product_id::text);
  v_cost_currency:=public.erp_v764_definition_currency(
    p_company_id,'product',v_product
  );

  select coalesce(sum(il.quantity),0) into v_issued
  from public.erp_maintenance_material_issue_lines il
  join public.erp_maintenance_material_issues i
    on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
  where il.company_id=p_company_id and il.maintenance_part_id=p_part_id;
  v_remaining:=mp.quantity-v_issued;
  if p_quantity>v_remaining then
    raise exception 'maintenance_issue_exceeds_remaining:%',v_remaining;
  end if;

  select * into w
  from public.erp_warehouses
  where company_id=p_company_id and id=p_warehouse_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_issue_warehouse_invalid'; end if;
  if lower(coalesce(w.data->>'isActive',w.data->>'active','true')) in ('false','0','no') then
    raise exception 'maintenance_issue_warehouse_inactive';
  end if;

  select * into ws
  from public.erp_warehouse_stock
  where company_id=p_company_id and not is_deleted
    and coalesce(data->>'warehouseId',data->>'warehouse_id')=p_warehouse_id
    and coalesce(data->>'productId',data->>'product_id')=v_product
  for update;
  if not found or public.erp_try_numeric(ws.data->>'quantity',0)
      -public.erp_try_numeric(ws.data->>'reservedQuantity',0)<p_quantity then
    raise exception 'maintenance_insufficient_stock:%',mp.product_name;
  end if;

  insert into public.erp_maintenance_material_issues(
    id,company_id,maintenance_order_id,effective_at,created_by
  ) values(p_issue_id,p_company_id,p_order_id,v_effective,auth.uid());
  insert into public.erp_maintenance_material_issue_lines(
    company_id,issue_id,maintenance_order_id,maintenance_part_id,
    product_id,warehouse_id,quantity
  ) values(
    p_company_id,p_issue_id,p_order_id,p_part_id,
    v_product,p_warehouse_id,p_quantity
  );

  update public.erp_warehouse_stock
  set data=data||jsonb_build_object(
      'quantity',public.erp_try_numeric(data->>'quantity',0)-p_quantity,
      'updatedAt',now()
    ),
    updated_at=now(),updated_by=auth.uid()
  where id=ws.id;

  v_needed:=p_quantity;
  for l in
    select * from public.erp_inventory_cost_layers q
    where q.company_id=p_company_id and q.item_type='product'
      and q.item_id=v_product and q.warehouse_id=p_warehouse_id
      and q.status in ('active','consumed') and q.remaining_quantity>0
      and q.effective_at<=v_effective
    order by q.effective_at,q.created_at,q.id
    for update
  loop
    exit when v_needed<=0;
    if upper(l.currency)<>v_cost_currency then
      raise exception 'maintenance_fifo_currency_definition_mismatch:%:%:%',
        v_product,upper(l.currency),v_cost_currency;
    end if;
    v_take:=least(v_needed,l.remaining_quantity);
    update public.erp_inventory_cost_layers
    set remaining_quantity=remaining_quantity-v_take,
        status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
        updated_at=now(),updated_by=auth.uid()
    where id=l.id;
    insert into public.erp_inventory_fifo_consumptions(
      company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,
      warehouse_id,quantity,unit_cost,effective_at,status
    ) values(
      p_company_id,p_issue_id,p_order_id,l.id,'product',v_product,
      p_warehouse_id,v_take,l.unit_cost,v_effective,'active'
    );
    v_cost:=v_cost+v_take*l.unit_cost;
    v_needed:=v_needed-v_take;
  end loop;
  if v_needed>0 then
    raise exception 'insufficient_maintenance_cost_layers:%',v_product;
  end if;

  if v_cost>0 then
    v_accounts:=public.erp_maintenance_bound_accounts(
      p_company_id,v_product,coalesce(o.currency_code,v_cost_currency),false
    );
    if upper(v_accounts->>'costCurrency')<>v_cost_currency then
      raise exception 'maintenance_cost_account_currency_mismatch:%:%:%',
        v_product,v_accounts->>'costCurrency',v_cost_currency;
    end if;
    v_cost_lines:=jsonb_build_array(
      jsonb_build_object(
        'accountId',v_accounts->>'costExpenseAccountId',
        'debit',round(v_cost,6),'credit',0,'currency',v_cost_currency,
        'description','Maintenance material issue cost',
        'itemId',v_product,'maintenanceOrderId',p_order_id,
        'maintenanceIssueId',p_issue_id,'quantity',p_quantity
      ),
      jsonb_build_object(
        'accountId',v_accounts->>'assetAccountId',
        'debit',0,'credit',round(v_cost,6),'currency',v_cost_currency,
        'description','Maintenance inventory issue',
        'itemId',v_product,'maintenanceOrderId',p_order_id,
        'maintenanceIssueId',p_issue_id,'quantity',p_quantity
      )
    );
    v_cost_journal:=public.erp_phase2_insert_journal_at(
      p_company_id,'maintenance_material_issue_cost',p_issue_id::text,
      public.erp_next_document_number(
        p_company_id,'maintenance_material_issue_cost_journal','MMIC',v_effective
      ),
      'Maintenance material issue '||o.order_number,
      v_cost_currency,v_cost_lines,v_effective
    );
    update public.erp_inventory_fifo_consumptions
    set journal_entry_id=v_cost_journal
    where company_id=p_company_id and delivery_id=p_issue_id
      and sales_order_id=p_order_id and status='active';
  end if;

  update public.erp_maintenance_material_issue_lines
  set actual_cost=v_cost
  where company_id=p_company_id and issue_id=p_issue_id;
  update public.erp_maintenance_material_issues
  set total_cost=v_cost,journal_entry_id=v_cost_journal
  where company_id=p_company_id and id=p_issue_id;

  perform public.erp_inventory_insert_movement(
    p_company_id,v_product,p_warehouse_id,'maintenance_out',-p_quantity,
    v_cost/p_quantity,'maintenance_issue',p_issue_id::text,
    'Maintenance material issue '||o.order_number
  );
  perform public.erp_inventory_refresh_product(p_company_id,v_product);
  perform public.erp_r57_refresh_maintenance_issue_costs(p_company_id,p_order_id);

  if not exists(
    select 1 from public.erp_maintenance_parts x
    where x.company_id=p_company_id and x.maintenance_order_id=p_order_id
      and not x.is_deleted and x.line_type<>'service'
      and x.quantity>(
        select coalesce(sum(il.quantity),0)
        from public.erp_maintenance_material_issue_lines il
        join public.erp_maintenance_material_issues i
          on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
        where il.company_id=p_company_id and il.maintenance_part_id=x.id
      )
  ) then
    update public.erp_maintenance_orders
    set workflow_stage='stock_issue_approved',
        stock_issue_number=case
          when stock_issue_number is null or stock_issue_number='PENDING' then
            public.erp_next_document_number(
              p_company_id,'maintenance_stock_issue','MSI',o.maintenance_date
            )
          else stock_issue_number
        end,
        updated_at=now()
    where id=p_order_id;
  end if;

  return jsonb_build_object(
    'issueId',p_issue_id,'idempotent',false,'quantity',p_quantity,
    'actualCost',round(v_cost,6),'costCurrency',v_cost_currency,
    'journalEntryId',v_cost_journal,'remaining',v_remaining-p_quantity
  );
end;
$$;

revoke all on function public.erp_r57_execute_maintenance_material_issue(
  uuid,uuid,uuid,uuid,text,numeric,timestamptz
) from public,anon,authenticated;
grant execute on function public.erp_r57_execute_maintenance_material_issue(
  uuid,uuid,uuid,uuid,text,numeric,timestamptz
) to service_role;

commit;
