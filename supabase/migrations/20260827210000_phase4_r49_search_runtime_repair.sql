-- Phase 4 runtime repair: keep the latest R49 global-search contract valid.
-- erp_records has updated_at but no created_at column. The function also
-- delegates to runtime functions, so it intentionally remains VOLATILE.
create or replace function public.erp_r49_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_limit integer:=greatest(1,least(coalesce(p_limit,50),200));
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_query,'')))<2 then return; end if;

  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then
    raise exception 'company_not_found' using errcode='P0002';
  end if;

  return query
  with base as (
    select row_payload,20 as rank
    from public.erp_r9_cloud_global_search(p_company_id,p_query,v_limit) as b(row_payload)
  ), opportunities as (
    select jsonb_build_object(
      'id',r.record_id,
      'type','الفرص التجارية',
      'title',coalesce(nullif(r.payload->>'title',''),nullif(r.payload->>'opportunityNumber',''),'فرصة تجارية'),
      'subtitle',concat_ws(' • ',nullif(r.payload->>'opportunityNumber',''),nullif(r.payload->>'customerName',''),nullif(r.payload->>'stage','')),
      'route','/customer-service',
      'permission','customer_service.view',
      'icon','opportunity',
      'status',coalesce(nullif(r.payload->>'status',''),nullif(r.payload->>'stage',''),'pending'),
      'amount',public.erp_try_numeric(r.payload->>'expectedValue',0),
      'currency',case when upper(coalesce(r.payload->>'currency','')) in ('USD','IQD') then upper(r.payload->>'currency') else null end,
      'date',coalesce(nullif(r.payload->>'updatedAt',''),nullif(r.payload->>'createdAt',''),r.updated_at::text)
    ) as row_payload,
    10 as rank
    from public.erp_records r
    where r.company_id=v_slug
      and r.entity_type='opportunities'
      and r.deleted_at is null
      and (
        public.is_company_admin(p_company_id)
        or public.erp_cloud_user_has_permission(p_company_id,'customer_service.view')
      )
      and r.payload::text ilike '%'||btrim(p_query)||'%'
  )
  select x.row_payload
  from (
    select row_payload,rank from opportunities
    union all
    select row_payload,rank from base
  ) x
  order by x.rank,coalesce(x.row_payload->>'date','') desc
  limit v_limit;
end;
$$;

revoke all on function public.erp_r49_cloud_global_search(uuid,text,integer) from public,anon;
grant execute on function public.erp_r49_cloud_global_search(uuid,text,integer) to authenticated,service_role;
notify pgrst,'reload schema';
