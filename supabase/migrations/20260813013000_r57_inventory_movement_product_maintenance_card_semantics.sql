begin;

-- R57 Inventory Movement / Product Maintenance Card semantic closure.
--
-- 1) Movement source/destination is derived from the business document, not
--    inferred as "current warehouse -> current warehouse".
-- 2) Product/material cards expose maintenance history by vehicle without
--    exposing internal maintenance cost, FIFO cost, profit, or vehicle cost.
--
-- Forward-only. Historical migrations remain untouched.

create or replace function public.erp_r28_inventory_movement_log(
  p_company_id uuid,
  p_product_id text default null
) returns setof jsonb
language sql
stable
security definer
set search_path=public
as $$
with base as (
  select
    m.*,
    lower(coalesce(m.data->>'movementType',m.data->>'movement_type','')) as movement_type,
    lower(coalesce(m.data->>'referenceType',m.data->>'reference_type','')) as ref_type,
    coalesce(m.data->>'referenceId',m.data->>'reference_id') as ref_id,
    coalesce(m.data->>'warehouseId',m.data->>'warehouse_id') as warehouse_id,
    coalesce(m.data->>'productId',m.data->>'product_id') as product_id,
    public.erp_try_numeric(m.data->>'quantity',0) as movement_quantity
  from public.erp_inventory_movements as m
  where m.company_id=p_company_id
    and not m.is_deleted
    and (p_product_id is null or
         coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id)
    and public.erp_is_company_member(p_company_id)
),
enriched as (
  select
    b.*,
    d.parent_id as workflow_parent_id,
    d.document_number as workflow_document_number,
    d.created_by as workflow_created_by,

    po.id as purchase_order_id,
    po.order_number as purchase_order_number,
    po.supplier_id,
    so.id as sales_order_id,
    so.order_number as sales_order_number,
    so.customer_id as sales_customer_id,

    coalesce(
      nullif(s.data->>'name',''),
      nullif(concat_ws(' ',s.data->>'firstName',s.data->>'lastName'),''),
      nullif(po.supplier_id,'')
    ) as supplier_name,
    coalesce(
      nullif(sc.data->>'name',''),
      nullif(concat_ws(' ',sc.data->>'firstName',sc.data->>'lastName'),''),
      nullif(so.customer_id,'')
    ) as sales_customer_name,

    mi.id as maintenance_issue_id,
    mo.id as maintenance_order_id,
    mo.order_number as maintenance_order_number,
    mo.customer_id as maintenance_customer_id,
    coalesce(
      nullif(mo.customer_name,''),
      nullif(mc.data->>'name',''),
      nullif(concat_ws(' ',mc.data->>'firstName',mc.data->>'lastName'),''),
      mo.customer_id::text
    ) as maintenance_customer_name,
    coalesce(
      nullif(mo.car_name,''),
      concat_ws(' ',car.data->>'brand',car.data->>'model',car.data->>'year'),
      mo.car_id::text
    ) as maintenance_vehicle_name,

    wt.id as transfer_id,
    coalesce(
      wt.data->>'transferNumber',
      wt.data->>'transfer_number',
      b.ref_id
    ) as transfer_number,
    coalesce(
      wt.data->>'fromWarehouseId',
      wt.data->>'from_warehouse_id'
    ) as transfer_from_id,
    coalesce(
      wt.data->>'toWarehouseId',
      wt.data->>'to_warehouse_id'
    ) as transfer_to_id,

    coalesce(w.data->>'name',w.data->>'nameAr',w.data->>'nameEn',b.warehouse_id)
      as warehouse_name,
    coalesce(
      wf.data->>'name',wf.data->>'nameAr',wf.data->>'nameEn',
      wt.data->>'fromWarehouseName',wt.data->>'from_warehouse_name',
      wt.data->>'fromWarehouseId',wt.data->>'from_warehouse_id'
    ) as transfer_from_name,
    coalesce(
      wt_to.data->>'name',wt_to.data->>'nameAr',wt_to.data->>'nameEn',
      wt.data->>'toWarehouseName',wt.data->>'to_warehouse_name',
      wt.data->>'toWarehouseId',wt.data->>'to_warehouse_id'
    ) as transfer_to_name,

    coalesce(i.data->>'name',i.data->>'nameAr',i.data->>'nameEn',i.data->>'code',b.product_id)
      as product_name,
    coalesce(i.data->>'code','') as product_code,
    coalesce(pr.full_name,b.created_by::text,d.created_by::text) as performed_by,
    coalesce(
      d.effective_at,
      mo.maintenance_date,
      public.erp_try_timestamptz(
        coalesce(wt.data->>'transferDate',wt.data->>'transfer_date'),
        null
      ),
      b.created_at
    ) as operational_at
  from base as b
  left join public.erp_commercial_workflow_documents as d
    on d.company_id=b.company_id
   and d.id::text=b.ref_id

  left join public.erp_purchase_orders_cloud as po
    on po.company_id=b.company_id
   and (
        po.id=d.parent_id
        or (
          d.id is null
          and b.ref_type like 'purchase%'
          and po.id::text=b.ref_id
        )
   )
  left join public.erp_sales_orders_cloud as so
    on so.company_id=b.company_id
   and (
        so.id=d.parent_id
        or (
          d.id is null
          and b.ref_type like 'sales%'
          and so.id::text=b.ref_id
        )
   )
  left join public.erp_suppliers as s
    on s.company_id=b.company_id
   and s.id=po.supplier_id
   and not s.is_deleted
  left join public.erp_customers as sc
    on sc.company_id=b.company_id
   and sc.id=so.customer_id
   and not sc.is_deleted

  left join public.erp_maintenance_material_issues as mi
    on mi.company_id=b.company_id
   and mi.id::text=b.ref_id
   and (
     b.ref_type in ('maintenance_issue','maintenance_issue_reversal')
     or b.movement_type in ('maintenance_out','maintenance_return')
   )
  left join public.erp_maintenance_orders as mo
    on mo.company_id=b.company_id
   and (
     mo.id=mi.maintenance_order_id
     or (
       mi.id is null
       and b.ref_type like 'maintenance%'
       and mo.id::text=b.ref_id
     )
   )
  left join public.erp_customers as mc
    on mc.company_id=b.company_id
   and mc.id=mo.customer_id::text
   and not mc.is_deleted
  left join public.erp_cars as car
    on car.company_id=b.company_id
   and car.id=mo.car_id::text
   and not car.is_deleted

  left join public.erp_warehouse_transfers as wt
    on wt.company_id=b.company_id
   and wt.id=b.ref_id
   and (
     b.ref_type in ('warehouse_transfer','inventory_transfer')
     or b.movement_type in ('transfer_in','transfer_out')
   )
  left join public.erp_warehouses as wf
    on wf.company_id=b.company_id
   and wf.id=coalesce(
     wt.data->>'fromWarehouseId',
     wt.data->>'from_warehouse_id'
   )
   and not wf.is_deleted
  left join public.erp_warehouses as wt_to
    on wt_to.company_id=b.company_id
   and wt_to.id=coalesce(
     wt.data->>'toWarehouseId',
     wt.data->>'to_warehouse_id'
   )
   and not wt_to.is_deleted

  left join public.erp_warehouses as w
    on w.company_id=b.company_id
   and w.id=b.warehouse_id
   and not w.is_deleted
  left join public.erp_inventory as i
    on i.company_id=b.company_id
   and i.id=b.product_id
   and not i.is_deleted
  left join public.profiles as pr
    on pr.id=coalesce(d.created_by,b.created_by)
),
semantic as (
  select
    e.*,
    case
      -- A warehouse transfer has one business direction for both audit rows.
      when e.transfer_id is not null
        or e.ref_type in ('warehouse_transfer','inventory_transfer')
        or e.movement_type in ('transfer_in','transfer_out')
      then coalesce(
        e.transfer_from_name,
        e.data->>'fromWarehouseName',
        e.data->>'from_warehouse_name',
        case when e.movement_type='transfer_out' then e.warehouse_name end,
        'Source warehouse'
      )

      -- Purchase and its reversal.
      when e.purchase_order_id is not null
        or e.ref_type like 'purchase%'
        or e.movement_type in (
          'purchase','purchase_in','purchase_receipt','purchase_cancel',
          'purchase_return','purchase_reversal','receipt_in','receipt_return'
        )
      then case when e.movement_quantity>=0
        then coalesce(e.supplier_name,'Supplier')
        else e.warehouse_name
      end

      -- Sale and its reversal.
      when e.sales_order_id is not null
        or e.ref_type like 'sales%'
        or e.movement_type in (
          'sale','sale_out','sales_out','sale_cancel','sale_return',
          'sale_reversal','delivery_out','sales_return'
        )
      then case when e.movement_quantity<=0
        then e.warehouse_name
        else coalesce(e.sales_customer_name,'Customer')
      end

      -- Maintenance issue and exact-event reversal/delete.
      when e.maintenance_order_id is not null
        or e.ref_type like 'maintenance%'
        or e.movement_type in ('maintenance_out','maintenance_return')
      then case when e.movement_quantity<=0
        then e.warehouse_name
        else coalesce(e.maintenance_customer_name,'Customer')
      end

      when e.movement_type='opening'
        then 'Opening balance'
      when e.movement_type in ('adjustment_in','adjustment_out')
        then case when e.movement_quantity>=0
          then 'Inventory adjustment'
          else e.warehouse_name
        end
      else coalesce(
        nullif(e.data->>'fromWarehouseName',''),
        nullif(e.data->>'from_warehouse_name',''),
        case when e.movement_quantity<=0 then e.warehouse_name end,
        'Inventory source'
      )
    end as source_name,

    case
      when e.transfer_id is not null
        or e.ref_type in ('warehouse_transfer','inventory_transfer')
        or e.movement_type in ('transfer_in','transfer_out')
      then coalesce(
        e.transfer_to_name,
        e.data->>'toWarehouseName',
        e.data->>'to_warehouse_name',
        case when e.movement_type='transfer_in' then e.warehouse_name end,
        'Destination warehouse'
      )

      when e.purchase_order_id is not null
        or e.ref_type like 'purchase%'
        or e.movement_type in (
          'purchase','purchase_in','purchase_receipt','purchase_cancel',
          'purchase_return','purchase_reversal','receipt_in','receipt_return'
        )
      then case when e.movement_quantity>=0
        then e.warehouse_name
        else coalesce(e.supplier_name,'Supplier')
      end

      when e.sales_order_id is not null
        or e.ref_type like 'sales%'
        or e.movement_type in (
          'sale','sale_out','sales_out','sale_cancel','sale_return',
          'sale_reversal','delivery_out','sales_return'
        )
      then case when e.movement_quantity<=0
        then coalesce(e.sales_customer_name,'Customer')
        else e.warehouse_name
      end

      when e.maintenance_order_id is not null
        or e.ref_type like 'maintenance%'
        or e.movement_type in ('maintenance_out','maintenance_return')
      then case when e.movement_quantity<=0
        then coalesce(e.maintenance_customer_name,'Customer')
        else e.warehouse_name
      end

      when e.movement_type='opening'
        then e.warehouse_name
      when e.movement_type in ('adjustment_in','adjustment_out')
        then case when e.movement_quantity>=0
          then e.warehouse_name
          else 'Inventory adjustment'
        end
      else coalesce(
        nullif(e.data->>'toWarehouseName',''),
        nullif(e.data->>'to_warehouse_name',''),
        case when e.movement_quantity>=0 then e.warehouse_name end,
        'Inventory destination'
      )
    end as destination_name
  from enriched as e
)
select
  s.data || jsonb_build_object(
    'id',s.id,
    'productId',s.product_id,
    'productName',s.product_name,
    'productCode',s.product_code,
    'warehouseId',s.warehouse_id,
    'warehouseName',s.warehouse_name,
    'movementDate',coalesce(s.data->>'movementDate',s.operational_at::text),
    'operationalAt',s.operational_at,
    'performedBy',s.performed_by,
    'referenceDocumentNumber',coalesce(
      s.transfer_number,
      s.maintenance_order_number,
      s.workflow_document_number,
      s.purchase_order_number,
      s.sales_order_number,
      nullif(s.data->>'referenceDocumentNumber',''),
      nullif(s.data->>'notes',''),
      s.ref_id
    ),
    'sourceName',s.source_name,
    'destinationName',s.destination_name,
    'maintenanceOrderId',s.maintenance_order_id,
    'maintenanceOrderNumber',s.maintenance_order_number,
    'vehicleName',s.maintenance_vehicle_name,
    '_cloudUpdatedAt',s.updated_at
  )
from semantic as s
order by s.operational_at desc,s.created_at desc,s.id desc
$$;

revoke all on function public.erp_r28_inventory_movement_log(uuid,text)
  from public,anon;
grant execute on function public.erp_r28_inventory_movement_log(uuid,text)
  to authenticated,service_role;


create or replace function public.erp_r57_product_maintenance_card(
  p_company_id uuid,
  p_product_id text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_product jsonb;
  v_history jsonb;
begin
  perform public.erp_active_company_context(p_company_id);

  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.view') then
    raise exception 'permission_denied:inventory.view' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;

  select jsonb_build_object(
    'id',i.id,
    'code',coalesce(i.data->>'code',''),
    'name',coalesce(
      nullif(i.data->>'name',''),
      nullif(i.data->>'nameAr',''),
      nullif(i.data->>'nameEn',''),
      i.data->>'code',
      i.id
    ),
    'unit',coalesce(nullif(i.data->>'unit',''),'—'),
    'category',coalesce(
      nullif(i.data->>'category',''),
      nullif(i.data->>'groupName',''),
      nullif(i.data->>'group_name',''),
      ''
    )
  )
  into v_product
  from public.erp_inventory as i
  where i.company_id=p_company_id
    and i.id=p_product_id
    and not i.is_deleted;

  if v_product is null then
    raise exception 'inventory_product_not_found' using errcode='P0002';
  end if;

  with relevant_parts as (
    select
      mp.company_id,
      mp.maintenance_order_id,
      array_agg(mp.id order by mp.created_at,mp.id) as part_ids,
      sum(mp.quantity)::numeric as requested_quantity,
      max(mp.product_name) as product_name
    from public.erp_maintenance_parts as mp
    join public.erp_maintenance_orders as o
      on o.company_id=mp.company_id
     and o.id=mp.maintenance_order_id
    where mp.company_id=p_company_id
      and coalesce(mp.source_product_id,mp.product_id::text)=p_product_id
      and mp.line_type<>'service'
      and (
        (not o.is_deleted and not mp.is_deleted)
        or (
          o.is_deleted
          and exists(
            select 1
            from public.erp_maintenance_material_issue_lines as hist_il
            where hist_il.company_id=mp.company_id
              and hist_il.maintenance_part_id=mp.id
          )
        )
      )
    group by mp.company_id,mp.maintenance_order_id
  ),
  history_rows as (
    select
      o.*,
      rp.part_ids,
      rp.requested_quantity,
      rp.product_name,
      coalesce(issue_totals.issued_quantity,0) as issued_quantity,
      coalesce(issue_totals.reversed_quantity,0) as reversed_quantity,
      coalesce(warehouse_rows.warehouses,'[]'::jsonb) as warehouses,
      coalesce(service_rows.services,'[]'::jsonb) as related_services,
      coalesce(payment_rows.preserved_unapplied_count,0) as preserved_unapplied_count,
      coalesce(
        nullif(o.customer_name,''),
        nullif(cust.data->>'name',''),
        nullif(concat_ws(' ',cust.data->>'firstName',cust.data->>'lastName'),''),
        o.customer_id::text
      ) as resolved_customer_name,
      coalesce(
        nullif(o.car_name,''),
        concat_ws(' ',car.data->>'brand',car.data->>'model',car.data->>'year'),
        o.car_id::text
      ) as resolved_car_name,
      coalesce(
        nullif(car.data->>'carNumber',''),
        nullif(car.data->>'car_number',''),
        nullif(car.data->>'vehicleNumber',''),
        nullif(car.data->>'vehicle_number',''),
        ''
      ) as car_number,
      coalesce(car.data->>'brand','') as car_brand,
      coalesce(car.data->>'model','') as car_model,
      coalesce(car.data->>'year','') as car_year,
      coalesce(car.data->>'chassis',car.data->>'vin','') as car_chassis,
      coalesce(
        car.data->>'plateNumber',
        car.data->>'plate_number',
        ''
      ) as car_plate
    from relevant_parts as rp
    join public.erp_maintenance_orders as o
      on o.company_id=rp.company_id
     and o.id=rp.maintenance_order_id
    left join public.erp_customers as cust
      on cust.company_id=o.company_id
     and cust.id=o.customer_id::text
     and not cust.is_deleted
    left join public.erp_cars as car
      on car.company_id=o.company_id
     and car.id=o.car_id::text
     and not car.is_deleted

    left join lateral (
      select
        coalesce(sum(il.quantity) filter(where iss.status='executed'),0)
          as issued_quantity,
        coalesce(sum(il.quantity) filter(where iss.status='reversed'),0)
          as reversed_quantity
      from public.erp_maintenance_material_issue_lines as il
      join public.erp_maintenance_material_issues as iss
        on iss.company_id=il.company_id
       and iss.id=il.issue_id
      where il.company_id=rp.company_id
        and il.maintenance_part_id=any(rp.part_ids)
    ) as issue_totals on true

    left join lateral (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'warehouseId',wq.warehouse_id,
            'warehouseName',wq.warehouse_name,
            'issuedQuantity',wq.issued_quantity,
            'reversedQuantity',wq.reversed_quantity
          )
          order by wq.warehouse_name,wq.warehouse_id
        ),
        '[]'::jsonb
      ) as warehouses
      from (
        select
          il2.warehouse_id,
          coalesce(
            wh.data->>'name',wh.data->>'nameAr',wh.data->>'nameEn',
            il2.warehouse_id
          ) as warehouse_name,
          coalesce(sum(il2.quantity) filter(where iss2.status='executed'),0)
            as issued_quantity,
          coalesce(sum(il2.quantity) filter(where iss2.status='reversed'),0)
            as reversed_quantity
        from public.erp_maintenance_material_issue_lines as il2
        join public.erp_maintenance_material_issues as iss2
          on iss2.company_id=il2.company_id
         and iss2.id=il2.issue_id
        left join public.erp_warehouses as wh
          on wh.company_id=il2.company_id
         and wh.id=il2.warehouse_id
         and not wh.is_deleted
        where il2.company_id=rp.company_id
          and il2.maintenance_part_id=any(rp.part_ids)
        group by il2.warehouse_id,
          coalesce(
            wh.data->>'name',wh.data->>'nameAr',wh.data->>'nameEn',
            il2.warehouse_id
          )
      ) as wq
    ) as warehouse_rows on true

    left join lateral (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'name',svc.product_name,
            'quantity',svc.quantity,
            'lineType',svc.line_type
          )
          order by svc.created_at,svc.id
        ),
        '[]'::jsonb
      ) as services
      from public.erp_maintenance_parts as svc
      where svc.company_id=o.company_id
        and svc.maintenance_order_id=o.id
        and svc.line_type='service'
        and (
          not svc.is_deleted
          or o.is_deleted
        )
    ) as service_rows on true

    left join lateral (
      select count(*) filter(where not p.is_deleted and p.is_unapplied)
        as preserved_unapplied_count
      from public.erp_maintenance_payments as p
      where p.company_id=o.company_id
        and p.maintenance_order_id=o.id
    ) as payment_rows on true
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',h.id,
        'orderNumber',h.order_number,
        'maintenanceDate',h.maintenance_date,
        'status',case when h.is_deleted then 'deleted' else h.status end,
        'workflowStage',case when h.is_deleted then 'deleted' else h.workflow_stage end,
        'isDeleted',h.is_deleted,
        'pricingType',h.pricing_type,

        'carId',h.car_id,
        'carName',h.resolved_car_name,
        'carNumber',h.car_number,
        'brand',h.car_brand,
        'model',h.car_model,
        'year',h.car_year,
        'chassis',h.car_chassis,
        'plateNumber',h.car_plate,

        'customerId',h.customer_id,
        'customerName',h.resolved_customer_name,

        'requestedQuantity',h.requested_quantity,
        'issuedQuantity',h.issued_quantity,
        'reversedQuantity',h.reversed_quantity,
        'remainingQuantity',greatest(h.requested_quantity-h.issued_quantity,0),
        'warehouseContributions',h.warehouses,

        'stockIssueNumber',h.stock_issue_number,
        'stockIssueStatus',case
          when h.is_deleted and h.reversed_quantity>0 then 'reversed'
          when h.issued_quantity<=0 then 'not_issued'
          when h.issued_quantity<h.requested_quantity then 'partial'
          else 'issued'
        end,

        'invoiceNumber',h.invoice_number,
        'invoiceStatus',case
          when h.invoice_number is null then 'none'
          when h.is_deleted then 'reversed'
          when h.workflow_stage='invoice_draft' then 'draft'
          when h.workflow_stage in ('invoice_approved','paid','completed','closed') then 'approved'
          else 'draft'
        end,
        'paymentStatus',case
          when h.is_deleted and h.preserved_unapplied_count>0 then 'preserved_unapplied'
          when h.is_deleted then 'none'
          when h.sale_price>0 and h.paid_amount+0.001>=h.sale_price then 'paid'
          when h.paid_amount>0 then 'partial'
          else 'unpaid'
        end,

        'relatedServices',h.related_services,
        'notes',h.notes,
        'cancelReason',h.cancel_reason
      )
      order by h.maintenance_date desc,h.created_at desc,h.id desc
    ),
    '[]'::jsonb
  )
  into v_history
  from history_rows as h;

  return jsonb_build_object(
    'product',v_product,
    'maintenanceHistory',v_history,
    'privacy',jsonb_build_object(
      'internalMaintenanceCostExcluded',true,
      'fifoCostExcluded',true,
      'vehicleCostExcluded',true,
      'profitExcluded',true
    )
  );
end;
$$;

revoke all on function public.erp_r57_product_maintenance_card(uuid,text)
  from public,anon;
grant execute on function public.erp_r57_product_maintenance_card(uuid,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
