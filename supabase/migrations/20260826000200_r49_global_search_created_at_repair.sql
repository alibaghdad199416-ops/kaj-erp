begin;

-- R49 runtime repair: erp_records has updated_at but no created_at column.
-- Keep the existing payload timestamps as the first preference and use the
-- actual normalized column only as the fallback.
create or replace function public.erp_r49_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language plpgsql
volatile
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
  if v_slug is null then raise exception 'company_not_found' using errcode='P0002'; end if;

  return query
  with base as (
    select
      case when b.row_payload->>'type'='القيود المحاسبية' then
        jsonb_set(
          b.row_payload,'{status}',
          to_jsonb(coalesce((select nullif(j.data->>'status','')
            from public.erp_journal_entries j
            where j.company_id=p_company_id
              and j.id::text=b.row_payload->>'id'
              and not j.is_deleted limit 1),'unknown')),true
        )
      else b.row_payload end as row_payload,
      20 as rank
    from public.erp_r9_cloud_global_search(p_company_id,p_query,v_limit) as b(row_payload)
  ), enriched_base as (
    select
      case when public.erp_r49_search_result_currency(p_company_id,row_payload) is null
        then row_payload
        else row_payload || jsonb_build_object(
          'currency',public.erp_r49_search_result_currency(p_company_id,row_payload)
        )
      end as row_payload,
      rank
    from base
  ), opportunities as (
    select jsonb_build_object(
      'id',r.record_id,
      'type','الفرص التجارية',
      'title',coalesce(nullif(r.payload->>'title',''),nullif(r.payload->>'opportunityNumber',''),'فرصة تجارية'),
      'subtitle',concat_ws(' • ',nullif(r.payload->>'opportunityNumber',''),nullif(r.payload->>'customerName',''),nullif(r.payload->>'stage','')),
      'route','/customer-service','permission','customer_service.view','icon','opportunity',
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
      and (public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'customer_service.view'))
      and (
        coalesce(r.payload->>'opportunityNumber','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'title','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'customerName','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'customerPhone','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'stage','') ilike '%'||btrim(p_query)||'%' or
        coalesce(r.payload->>'status','') ilike '%'||btrim(p_query)||'%'
      )
  )
  select x.row_payload
  from (
    select row_payload,rank from opportunities
    union all
    select row_payload,rank from enriched_base
  ) x
  order by x.rank,coalesce(x.row_payload->>'date','') desc
  limit v_limit;
end;
$$;

revoke all on function public.erp_r49_cloud_global_search(uuid,text,integer) from public,anon;
grant execute on function public.erp_r49_cloud_global_search(uuid,text,integer) to authenticated,service_role;

commit;
