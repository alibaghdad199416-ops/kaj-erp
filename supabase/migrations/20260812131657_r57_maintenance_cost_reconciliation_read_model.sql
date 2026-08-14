begin;

-- One bounded, read-only maintenance reconciliation contract. Requested cost
-- uses the line's captured cost basis; issued cost/quantity comes exclusively
-- from the R53/R54 FIFO consumptions created by material-issue approval.
create or replace function public.erp_r57_maintenance_cost_reconciliation(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_lines jsonb;
  v_warehouses jsonb;
  v_requested_material_cost numeric:=0;
  v_issued_material_cost numeric:=0;
  v_materials_invoiced numeric:=0;
  v_services_invoiced numeric:=0;
  v_labor_invoiced numeric:=0;
  v_has_invoice boolean:=false;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;

  select * into v_order
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then
    raise exception 'maintenance_order_not_found' using errcode='P0002';
  end if;

  v_has_invoice:=v_order.invoice_number is not null
    and v_order.invoice_number<>'PENDING'
    and v_order.workflow_stage in ('invoice_approved','paid','completed');

  with line_costs as (
    select mp.id,
      coalesce(mp.source_product_id,mp.product_id::text) product_id,
      mp.product_name,
      coalesce(mp.source_warehouse_id,mp.warehouse_id::text,
        v_order.source_warehouse_id,v_order.warehouse_id::text) warehouse_id,
      coalesce(w.data->>'name',w.data->>'nameAr',w.data->>'nameEn') warehouse_name,
      mp.line_type,mp.quantity::numeric requested_quantity,
      coalesce(mp.unit_cost,0) requested_unit_cost,
      coalesce(mp.unit_price,0) unit_price,
      coalesce(mp.line_total_price,mp.unit_price*mp.quantity,0) requested_invoice_value,
      coalesce(fc.issued_quantity,0) issued_quantity,
      coalesce(fc.issued_cost,0) issued_cost
    from public.erp_maintenance_parts mp
    left join public.erp_warehouses w on w.company_id=mp.company_id
      and w.id=coalesce(mp.source_warehouse_id,mp.warehouse_id::text) and not w.is_deleted
    left join lateral (
      select sum(c.quantity) issued_quantity,sum(c.total_cost) issued_cost
      from public.erp_inventory_fifo_consumptions c
      where c.company_id=mp.company_id and c.delivery_id=mp.maintenance_order_id
        and c.sales_order_id=mp.maintenance_order_id and c.status='active'
        and c.item_type='product'
        and c.item_id=coalesce(mp.source_product_id,mp.product_id::text)
        and c.warehouse_id=coalesce(mp.source_warehouse_id,mp.warehouse_id::text,
          v_order.source_warehouse_id,v_order.warehouse_id::text)
    ) fc on mp.line_type<>'service'
    where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted
  ), normalized as (
    select *,
      case when line_type='service' then 0 else requested_quantity*requested_unit_cost end requested_cost,
      case when v_has_invoice then requested_quantity else 0 end invoiced_quantity,
      case when v_has_invoice then requested_invoice_value else 0 end invoiced_value
    from line_costs
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'lineId',id,'productId',product_id,'description',product_name,
      'warehouseId',warehouse_id,'warehouseName',warehouse_name,'lineType',line_type,
      'requestedQuantity',requested_quantity,'issuedQuantity',issued_quantity,
      'invoicedQuantity',invoiced_quantity,'requestedUnitCost',requested_unit_cost,
      'requestedCost',requested_cost,'issuedActualCost',issued_cost,
      'unitInvoiceValue',unit_price,'invoicedValue',invoiced_value,
      'issuedNotInvoicedQuantity',greatest(issued_quantity-invoiced_quantity,0),
      'invoicedNotIssuedQuantity',case when line_type='service' then 0
        else greatest(invoiced_quantity-issued_quantity,0) end
    ) order by line_type,id),'[]'::jsonb),
    coalesce(sum(requested_cost) filter(where line_type<>'service'),0),
    coalesce(sum(issued_cost) filter(where line_type<>'service'),0),
    coalesce(sum(invoiced_value) filter(where line_type<>'service'),0),
    coalesce(sum(invoiced_value) filter(where line_type='service'),0)
  into v_lines,v_requested_material_cost,v_issued_material_cost,
    v_materials_invoiced,v_services_invoiced
  from normalized;

  select coalesce(jsonb_agg(jsonb_build_object(
    'warehouseId',warehouse_id,'warehouseName',warehouse_name,
    'issuedQuantity',issued_quantity,'issuedActualCost',issued_cost
  ) order by warehouse_name,warehouse_id),'[]'::jsonb)
  into v_warehouses
  from (
    select c.warehouse_id,
      coalesce(w.data->>'name',w.data->>'nameAr',w.data->>'nameEn',c.warehouse_id) warehouse_name,
      sum(c.quantity) issued_quantity,sum(c.total_cost) issued_cost
    from public.erp_inventory_fifo_consumptions c
    left join public.erp_warehouses w on w.company_id=c.company_id
      and w.id=c.warehouse_id and not w.is_deleted
    where c.company_id=p_company_id and c.delivery_id=p_order_id
      and c.sales_order_id=p_order_id and c.status='active' and c.item_type='product'
    group by c.warehouse_id,coalesce(w.data->>'name',w.data->>'nameAr',w.data->>'nameEn',c.warehouse_id)
  ) q;

  -- Maintenance currently stores one authoritative invoice total, without
  -- persisted discount/tax columns. The residual after explicit material and
  -- service line values is the labor invoice value; unavailable components
  -- stay JSON null instead of being invented as zero.
  v_labor_invoiced:=case when v_has_invoice then
    greatest(v_order.sale_price-v_materials_invoiced-v_services_invoiced,0)
    else 0 end;

  return jsonb_build_object(
    'orderId',v_order.id,'orderNumber',v_order.order_number,
    'currency',upper(v_order.currency_code),'workflowStage',v_order.workflow_stage,
    'hasApprovedInvoice',v_has_invoice,
    'requestedMaterialsCost',round(v_requested_material_cost,2),
    'issuedMaterialsActualCost',round(v_issued_material_cost,2),
    'laborCost',round(v_order.labor_cost,2),
    'additionalServicesCost',0,
    'totalOperationalCost',round(v_order.labor_cost+v_issued_material_cost,2),
    'materialsInvoiced',round(v_materials_invoiced,2),
    'laborInvoiced',round(v_labor_invoiced,2),
    'servicesInvoiced',round(v_services_invoiced,2),
    'discount',null,'tax',null,
    'totalInvoiced',case when v_has_invoice then round(v_order.sale_price,2) else 0 end,
    'paid',round(v_order.paid_amount,2),
    'outstanding',case when v_has_invoice then round(greatest(v_order.sale_price-v_order.paid_amount,0),2) else 0 end,
    'issuedNotInvoicedCost',case when v_has_invoice then
      round(greatest(v_issued_material_cost-v_materials_invoiced,0),2)
      else round(v_issued_material_cost,2) end,
    'invoicedNotIssuedValue',case when v_has_invoice then
      round(greatest(v_materials_invoiced-v_issued_material_cost,0),2) else 0 end,
    'materialDiscrepancy',abs(v_issued_material_cost-v_materials_invoiced)>0.01,
    'laborDiscrepancy',v_has_invoice and abs(v_order.labor_cost-v_labor_invoiced)>0.01,
    'lines',v_lines,'warehouses',v_warehouses
  );
end;
$$;

revoke all on function public.erp_r57_maintenance_cost_reconciliation(uuid,uuid)
  from public,anon;
grant execute on function public.erp_r57_maintenance_cost_reconciliation(uuid,uuid)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
