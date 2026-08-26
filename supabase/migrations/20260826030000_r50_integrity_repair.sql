begin;

-- R50 integrity repair: forward-only, data-preserving fixes for the remaining
-- schema/runtime blockers reported by PostgreSQL lint. No historical migration
-- is edited and no business data is deleted.

-- ---------------------------------------------------------------------------
-- Document processing jobs: this table is part of the document-intelligence
-- contract and must exist before operational health/RPC checks reference it.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_document_processing_jobs
  (like public.erp_contracts including all);

create index if not exists erp_document_processing_jobs_status_idx
  on public.erp_document_processing_jobs(
    company_id,
    ((data->>'status')),
    created_at
  );

alter table public.erp_document_processing_jobs enable row level security;

do $$
begin
  drop policy if exists tenant_access on public.erp_document_processing_jobs;
  create policy tenant_access
    on public.erp_document_processing_jobs
    for all
    using (public.erp_user_belongs_to_company(company_id))
    with check (public.erp_user_belongs_to_company(company_id));
exception when duplicate_object then
  null;
end $$;

-- ---------------------------------------------------------------------------
-- Canonical global search: erp_records has updated_at but does not expose a
-- created_at column. Keep the payload's createdAt as the first source and use
-- the normalized updated_at only as the database fallback.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r49_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language plpgsql
stable
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

  select slug into v_slug
  from public.companies
  where id=p_company_id;
  if v_slug is null then
    raise exception 'company_not_found' using errcode='P0002';
  end if;

  return query
  with base as (
    select
      case
        when b.row_payload->>'type'='القيود المحاسبية' then
          jsonb_set(
            b.row_payload,
            '{status}',
            to_jsonb(coalesce((
              select nullif(j.data->>'status','')
              from public.erp_journal_entries j
              where j.company_id=p_company_id
                and j.id::text=b.row_payload->>'id'
                and not j.is_deleted
              limit 1
            ),'unknown')),
            true
          )
        else b.row_payload
      end as row_payload,
      20 as rank
    from public.erp_r9_cloud_global_search(p_company_id,p_query,v_limit) as b(row_payload)
  ), enriched_base as (
    select
      case
        when public.erp_r49_search_result_currency(p_company_id,row_payload) is null
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
      'title',coalesce(
        nullif(r.payload->>'title',''),
        nullif(r.payload->>'opportunityNumber',''),
        'فرصة تجارية'
      ),
      'subtitle',concat_ws(' • ',
        nullif(r.payload->>'opportunityNumber',''),
        nullif(r.payload->>'customerName',''),
        nullif(r.payload->>'stage','')
      ),
      'route','/customer-service',
      'permission','customer_service.view',
      'icon','opportunity',
      'status',coalesce(
        nullif(r.payload->>'status',''),
        nullif(r.payload->>'stage',''),
        'pending'
      ),
      'amount',public.erp_try_numeric(r.payload->>'expectedValue',0),
      'currency',case
        when upper(coalesce(r.payload->>'currency','')) in ('USD','IQD')
          then upper(r.payload->>'currency')
        else null
      end,
      'date',coalesce(
        nullif(r.payload->>'updatedAt',''),
        nullif(r.payload->>'createdAt',''),
        r.updated_at::text
      )
    ) as row_payload,
    10 as rank
    from public.erp_records r
    where r.company_id=v_slug
      and r.entity_type='opportunities'
      and r.deleted_at is null
      and (
        public.is_company_admin(p_company_id)
        or public.erp_cloud_user_has_permission(
          p_company_id,'customer_service.view'
        )
      )
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

-- ---------------------------------------------------------------------------
-- Volatility correctness.
-- Security/read wrappers that call volatile routines must not be advertised
-- as STABLE. Conversion helpers that depend on timezone/date parsing are kept
-- STABLE rather than incorrectly IMMUTABLE. The extension-owned digest routine
-- is intentionally excluded.
-- ---------------------------------------------------------------------------
do $$
declare
  v_name text;
  v_proc record;
  v_volatile_names constant text[] := array[
    'erp_search_cloud_documents',
    'erp_r22_cash_health',
    'erp_v2300_get_commercial_order_complete_details',
    'erp_r9_cloud_cash_currency_summary',
    'erp_r9_cloud_trial_balance',
    'erp_r9_cloud_account_balance_before',
    'erp_r9_cloud_detailed_accounting_report',
    'erp_r9_cloud_cash_flow_hierarchy',
    'erp_r9_cloud_contextual_report',
    'erp_r9_cloud_model_report',
    'erp_r9_cloud_customer_service_report',
    'erp_r9_cloud_report_audit',
    'erp_r9_cloud_reports_summary',
    'erp_r9_cloud_dashboard_snapshot',
    'erp_get_cloud_current_document_blob',
    'erp_get_cloud_document',
    'erp_list_cloud_document_versions',
    'erp_list_cloud_document_permissions',
    'erp_r15_current_state_health',
    'erp_r49_get_sales_order_draft',
    'erp_r49_get_purchase_order_draft'
  ];
  v_stable_names constant text[] := array[
    'erp_try_date',
    'erp_try_timestamptz'
  ];
begin
  foreach v_name in array v_volatile_names loop
    for v_proc in
      select p.oid::regprocedure as signature
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop
      execute format('alter function %s volatile',v_proc.signature);
    end loop;
  end loop;

  foreach v_name in array v_stable_names loop
    for v_proc in
      select p.oid::regprocedure as signature
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop
      execute format('alter function %s stable',v_proc.signature);
    end loop;
  end loop;
end $$;

commit;
