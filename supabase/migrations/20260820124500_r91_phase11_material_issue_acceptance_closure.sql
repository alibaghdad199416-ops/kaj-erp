-- Quality Line ERP / KAJ ERP
-- Phase 11 R91 final material-issue acceptance closure.
-- Forward-only: enrich maintenance line descriptions and prevent duplicate
-- final material-issue notifications after the R90 draft/approval boundary.
begin;

-- ---------------------------------------------------------------------------
-- 1. Maintenance Details & Items: real item/service description.
--    The legacy typed row remains unchanged; the R9 JSON boundary enriches it
--    from the source Product master while respecting maintenance.items field
--    visibility. No new business value is invented when the product has no
--    description; product name is the final display fallback.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_get_cloud_maintenance_order_lines(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(
      p_company_id,'maintenance',to_jsonb(x),'maintenance.view'
    )
    || case
      when public.erp_cloud_user_can_view_field(
        p_company_id,'maintenance','items','maintenance.view'
      ) then jsonb_build_object(
        'description',coalesce(
          nullif(btrim(i.data->>'description'),''),
          nullif(btrim(i.data->>'descriptionAr'),''),
          nullif(btrim(i.data->>'descriptionEn'),''),
          nullif(btrim(i.data->>'notes'),''),
          nullif(btrim(x."productName"),''),
          ''
        )
      )
      else '{}'::jsonb
    end
  from public.erp_get_cloud_maintenance_order_lines(p_company_id,p_order_id) x
  join public.erp_maintenance_parts mp
    on mp.company_id=p_company_id and mp.id=x.id and not mp.is_deleted
  left join public.erp_inventory i
    on i.company_id=mp.company_id
   and i.id=coalesce(mp.source_product_id,mp.product_id::text)
   and not i.is_deleted
  where exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
      and public.erp_r84_record_visible(
        p_company_id,'maintenance',o.created_by,null
      )
  );
$$;

revoke all on function public.erp_r9_get_cloud_maintenance_order_lines(uuid,uuid)
  from public,anon;
grant execute on function public.erp_r9_get_cloud_maintenance_order_lines(uuid,uuid)
  to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 2. R90 owns maintenance material-issue approval notifications.
--    Before R90, the order-stage trigger emitted one event when the complete
--    stock issue reached stock_issue_approved. R90 now supports multiple
--    approved issue drafts and emits one durable event per approved draft.
--    Suppress the old final-stage material-issue branch to avoid a duplicate
--    event on the final approved draft. Invoice/payment notifications remain
--    owned by the R88 trigger.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r88_maintenance_order_notification()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_event text;
  v_reference text;
  v_actor text:='';
  v_car text;
  v_key text;
begin
  if new.is_deleted then return new; end if;
  if tg_op<>'UPDATE' then return new; end if;

  if new.workflow_stage is distinct from old.workflow_stage then
    v_event:=case new.workflow_stage
      -- R90 approved issue drafts own maintenance_material_issue events.
      when 'invoice_approved' then 'maintenance_invoice'
      else null end;
  end if;
  if v_event is null and new.paid_amount>old.paid_amount then
    v_event:='maintenance_payment';
  end if;
  if v_event is null then return new; end if;

  select coalesce(full_name,'') into v_actor
  from public.profiles where id=coalesce(new.updated_by,new.created_by,auth.uid());
  v_car:=coalesce(nullif(new.car_name,''),new.car_id::text);
  v_reference:=case v_event
    when 'maintenance_invoice' then coalesce(new.invoice_number,new.order_number)
    else new.order_number end;
  v_key:=format('r88:%s:%s:%s',v_event,new.id::text,new.updated_at::text);

  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(new.company_id,gen_random_uuid(),jsonb_build_object(
    'eventKey',v_key,'eventType',v_event,'event',v_event,
    'type','success','module','maintenance',
    'documentReference',v_reference,'orderReference',new.order_number,
    'actorUserId',coalesce(new.updated_by,new.created_by,auth.uid()),
    'actorUser',v_actor,'dateTime',new.updated_at,
    'carId',new.car_id,'carName',v_car,
    'customerName',coalesce(new.customer_name,''),
    'amount',case when v_event='maintenance_payment'
      then greatest(new.paid_amount-old.paid_amount,0)
      else new.sale_price end,
    'currency',upper(new.currency_code),
    'referenceType','maintenance_order','referenceId',new.id::text,
    'deepLink','/maintenance',
    'titleAr',case v_event
      when 'maintenance_invoice' then 'تم تصديق فاتورة الصيانة'
      else 'تم تسجيل دفعة صيانة' end,
    'titleEn',case v_event
      when 'maintenance_invoice' then 'Maintenance invoice posted'
      else 'Maintenance payment recorded' end,
    'bodyAr',coalesce(v_actor,'')||' • '||v_reference||' • '||v_car,
    'bodyEn',coalesce(v_actor,'')||' • '||v_reference||' • '||v_car,
    'createdAt',now()
  )) on conflict do nothing;
  return new;
end;
$$;

-- Trigger remains attached; CREATE OR REPLACE updates its function body.
revoke all on function public.erp_r88_maintenance_order_notification()
  from public,anon,authenticated;
grant execute on function public.erp_r88_maintenance_order_notification()
  to service_role;

notify pgrst,'reload schema';
commit;
