-- Repair installations where migration 20260803050000 was already applied
-- with a stale company_slug projection from the UUID context overload.

begin;

create or replace function public.erp_cloud_customer_service_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns setof jsonb language plpgsql security definer set search_path=public as $$
declare v_slug text;
begin
  perform public.erp_active_company_context(p_company_id);
  select coalesce(nullif(c.slug,''),p_company_id::text)
    into v_slug
    from public.companies c
   where c.id=p_company_id;
  v_slug:=coalesce(v_slug,p_company_id::text);

  if p_module in ('customer_service','opportunities') then
    return query
    with opportunities as (
      select r.record_id,r.payload,r.updated_at,r.created_by
        from public.erp_records r
       where r.company_id=v_slug and r.entity_type='opportunities' and r.deleted_at is null
         and (p_start_date is null or coalesce(public.erp_try_timestamptz(r.payload->>'createdAt',r.updated_at),r.updated_at)::date>=p_start_date)
         and (p_end_date is null or coalesce(public.erp_try_timestamptz(r.payload->>'createdAt',r.updated_at),r.updated_at)::date<=p_end_date)
    ), details as (
      select jsonb_build_array(
        coalesce(payload->>'opportunityNumber',record_id),
        coalesce(payload->>'title',''),
        coalesce(payload->>'customerName',''),
        coalesce(payload->>'customerPhone',''),
        coalesce(payload->>'source',''),
        coalesce(payload->>'status','pending'),
        coalesce(payload->>'assignedUserName',''),
        coalesce(payload->>'createdByUserName',''),
        coalesce(payload->>'expectedValue','0'),
        coalesce(payload->>'carName',''),
        coalesce(payload->>'invoiceNumber',payload->>'salesOrderNumber',''),
        coalesce(payload->>'followUpDate',''),
        coalesce(payload->>'closedAt',''),
        coalesce(payload->>'createdAt',updated_at::text),
        coalesce(payload->>'notes','')
      ) row_data from opportunities
    ), status_summary as (
      select lower(coalesce(payload->>'status','pending')) status,
             count(*) count_value,
             sum(public.erp_try_numeric(payload->>'expectedValue',0)) value_total
        from opportunities group by lower(coalesce(payload->>'status','pending'))
    ), owner_summary as (
      select coalesce(nullif(payload->>'assignedUserName',''),'غير محدد') owner_name,
             count(*) count_value,
             sum(public.erp_try_numeric(payload->>'expectedValue',0)) value_total
        from opportunities group by coalesce(nullif(payload->>'assignedUserName',''),'غير محدد')
    )
    select jsonb_build_object(
      'key','opportunities_details','title','Opportunities / الفرص التجارية',
      'columns',jsonb_build_array('opportunityNumber','title','customer','phone','source','status','assignedUser','createdBy','expectedValue','vehicle','salesOrderNumber','followUpDate','closedAt','createdAt','notes'),
      'rows',coalesce((select jsonb_agg(row_data) from details),'[]'::jsonb)
    )
    union all
    select jsonb_build_object(
      'key','opportunities_status','title','Opportunity Status / حالات الفرص',
      'columns',jsonb_build_array('status','count','expectedValue'),
      'rows',coalesce((select jsonb_agg(jsonb_build_array(status,count_value,value_total)) from status_summary),'[]'::jsonb)
    )
    union all
    select jsonb_build_object(
      'key','customer_service_owners','title','Customer Service Owners / مسؤولو خدمة العملاء',
      'columns',jsonb_build_array('assignedUser','count','expectedValue'),
      'rows',coalesce((select jsonb_agg(jsonb_build_array(owner_name,count_value,value_total)) from owner_summary),'[]'::jsonb)
    );
    return;
  end if;
  raise exception 'وحدة تقرير خدمة العملاء غير مدعومة';
end $$;

revoke all on function public.erp_cloud_customer_service_report(uuid,text,date,date) from public,anon;
grant execute on function public.erp_cloud_customer_service_report(uuid,text,date,date) to authenticated;

commit;
