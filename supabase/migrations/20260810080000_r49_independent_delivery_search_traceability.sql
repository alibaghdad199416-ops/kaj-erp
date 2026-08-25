begin;

-- R49 independent delivery audit: make global discovery CRM-complete, tenant-safe,
-- currency-aware, and conservative about journal state. The legacy search remains
-- available for compatibility; Flutter moves to this canonical wrapper.
create or replace function public.erp_r49_search_result_currency(
  p_company_id uuid,
  p_row jsonb
) returns text
language plpgsql
stable
security invoker
set search_path=public
as $$
declare
  v_type text:=coalesce(p_row->>'type','');
  v_id text:=coalesce(p_row->>'id','');
  v_currency text;
begin
  if v_type='السيارات' then
    select upper(nullif(coalesce(data->>'saleCurrency',data->>'sale_currency',data->>'currency'),''))
      into v_currency from public.erp_cars
      where company_id=p_company_id and id::text=v_id and not is_deleted limit 1;
  elsif v_type='المنتجات' then
    select upper(nullif(coalesce(data->>'saleCurrency',data->>'sale_currency',data->>'currency'),''))
      into v_currency from public.erp_inventory
      where company_id=p_company_id and id::text=v_id and not is_deleted limit 1;
  elsif v_type='أوامر البيع' then
    select upper(nullif(currency,'')) into v_currency from public.erp_sales_orders_cloud
      where company_id=p_company_id and id::text=v_id and not is_deleted limit 1;
  elsif v_type='أوامر الشراء' then
    select upper(nullif(currency,'')) into v_currency from public.erp_purchase_orders_cloud
      where company_id=p_company_id and id::text=v_id and not is_deleted limit 1;
  elsif v_type in ('التجهيز','الاستلام','الفواتير') then
    select upper(nullif(coalesce(payload->>'currency',payload->>'currencyCode'),''))
      into v_currency from public.erp_commercial_workflow_documents
      where company_id=p_company_id and id::text=v_id and not is_deleted limit 1;
  elsif v_type='القيود المحاسبية' then
    select upper(nullif(data->>'currency','')) into v_currency from public.erp_journal_entries
      where company_id=p_company_id and id::text=v_id and not is_deleted limit 1;
  elsif v_type='الدفعات' then
    select upper(nullif(coalesce(data->>'currencyCode',data->>'currency'),''))
      into v_currency from public.erp_installments
      where company_id=p_company_id and id::text=v_id and not is_deleted limit 1;
  end if;
  if v_currency not in ('USD','IQD') then return null; end if;
  return v_currency;
end $$;

revoke all on function public.erp_r49_search_result_currency(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.erp_r49_search_result_currency(uuid,jsonb) to service_role;

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
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then raise exception 'company_not_found' using errcode='P0002'; end if;

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
      'subtitle',concat_ws(' • ',
        nullif(r.payload->>'opportunityNumber',''),
        nullif(r.payload->>'customerName',''),
        nullif(r.payload->>'stage','')
      ),
      'route','/customer-service',
      'permission','customer_service.view',
      'icon','opportunity',
      'status',coalesce(nullif(r.payload->>'status',''),nullif(r.payload->>'stage',''),'pending'),
      'amount',public.erp_try_numeric(r.payload->>'expectedValue',0),
      'currency',case when upper(coalesce(r.payload->>'currency','')) in ('USD','IQD') then upper(r.payload->>'currency') else null end,
      'date',coalesce(nullif(r.payload->>'updatedAt',''),nullif(r.payload->>'createdAt',''),r.updated_at::text,r.created_at::text)
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
end $$;

revoke all on function public.erp_r49_cloud_global_search(uuid,text,integer) from public,anon;
grant execute on function public.erp_r49_cloud_global_search(uuid,text,integer) to authenticated,service_role;



-- Cashbox configuration is an accounting action, not generic master-data access.
-- Preserve legacy active rows once, then make malformed future reads fail closed.
update public.erp_cash_accounts
set data=coalesce(data,'{}'::jsonb)||jsonb_build_object('isActive',true,'is_active',true),
    updated_at=now(),updated_by=coalesce(updated_by,auth.uid())
where not is_deleted
  and not (coalesce(data,'{}'::jsonb) ? 'isActive')
  and not (coalesce(data,'{}'::jsonb) ? 'is_active');

create or replace function public.erp_r42_save_cash_account(
  p_company_id uuid,p_account jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_in jsonb:=coalesce(p_account,'{}'::jsonb);
  v_id text:=btrim(coalesce(v_in->>'id',''));
  v_old jsonb;
  v_guarded jsonb;
  v_ledger text;
  v_currency text;
  v_active boolean;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if v_id='' then raise exception 'cashbox_id_required' using errcode='22023'; end if;

  select data into v_old from public.erp_cash_accounts
  where company_id=p_company_id and id=v_id and not is_deleted;

  if v_old is null then
    if not public.is_company_admin(p_company_id)
       and not public.erp_cloud_user_has_permission(p_company_id,'accounting.create') then
      raise exception 'permission_denied:accounting.create' using errcode='42501';
    end if;
  elsif not public.is_company_admin(p_company_id)
        and not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then
    raise exception 'permission_denied:accounting.update' using errcode='42501';
  end if;

  v_guarded:=public.erp_r24_guard_cash_account_payload(
    p_company_id,coalesce(v_old,'{}'::jsonb),v_in
  );
  v_ledger:=nullif(btrim(coalesce(
    v_guarded->>'canonical',v_guarded->>'account_id',v_guarded->>'accountId',
    v_guarded->>'ledgerAccountId',''
  )), '');
  if v_ledger is null then raise exception 'cashbox_ledger_account_required' using errcode='23503'; end if;

  v_currency:=upper(btrim(coalesce(v_guarded->>'currency','')));
  if v_currency not in ('USD','IQD') then
    raise exception 'cashbox_currency_required' using errcode='22023';
  end if;
  if not (v_guarded ? 'isActive') and not (v_guarded ? 'is_active') then
    raise exception 'cashbox_active_state_required' using errcode='22023';
  end if;
  v_active:=public.erp_try_boolean(coalesce(v_guarded->>'isActive',v_guarded->>'is_active'),'false');

  v_guarded:=v_guarded||jsonb_build_object(
    'accountId',v_ledger,'account_id',v_ledger,'canonical',v_ledger,
    'ledgerAccountId',v_ledger,'currency',v_currency,
    'isActive',v_active,'is_active',v_active,
    'schemaVersion',49,'schema_version',49
  );
  v_result:=public.erp_r28_save_cash_account(p_company_id,v_guarded);
  return v_result||jsonb_build_object(
    'accountId',v_ledger,'account_id',v_ledger,'canonical',v_ledger,
    'ledgerAccountId',v_ledger,'currency',v_currency,
    'isActive',v_active,'is_active',v_active,
    'schemaVersion',49,'schema_version',49
  );
end $$;

revoke all on function public.erp_r42_save_cash_account(uuid,jsonb) from public,anon;
grant execute on function public.erp_r42_save_cash_account(uuid,jsonb) to authenticated,service_role;

create or replace function public.erp_delete_cloud_cash_account(
  p_company_id uuid,p_cash_account_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'accounting.delete') then
    raise exception 'permission_denied:accounting.delete' using errcode='42501';
  end if;
  if exists(
    select 1 from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and coalesce(data->>'cashAccountId',data->>'cash_account_id')=p_cash_account_id
  ) then
    raise exception 'cashbox_has_financial_movements' using errcode='23503';
  end if;
  update public.erp_cash_accounts
  set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_cash_account_id and not is_deleted;
end $$;

revoke all on function public.erp_delete_cloud_cash_account(uuid,text) from public,anon;
grant execute on function public.erp_delete_cloud_cash_account(uuid,text) to authenticated,service_role;

notify pgrst,'reload schema';

-- Independent failure-resistance closure: manual cash vouchers use the same
-- receipt/payment permission contract as Flutter. The low-level posting
-- primitive is internal-only; specialized workflows keep calling it inside
-- their already-authorized SECURITY DEFINER transaction.


revoke all on function public.erp_post_cloud_cash_transaction(uuid,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.erp_post_cloud_cash_transaction(uuid,jsonb,boolean) to service_role;

create or replace function public.erp_r9_post_cloud_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_old jsonb;
  v_guarded jsonb;
  v_id text:=btrim(coalesce(p_transaction->>'id',''));
  v_type text:=lower(btrim(coalesce(p_transaction->>'type','')));
  v_old_type text;
  v_permission text;
  v_old_permission text;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if v_id='' then raise exception 'cash_transaction_id_required' using errcode='22023'; end if;
  if v_type not in ('receipt','payment') then raise exception 'cash_transaction_type_invalid' using errcode='22023'; end if;

  select data into v_old from public.erp_cash_transactions
   where company_id=p_company_id and id=v_id and not is_deleted;
  if p_replace and v_old is null then raise exception 'cash_transaction_not_found' using errcode='P0002'; end if;
  if not p_replace and v_old is not null then raise exception 'cash_transaction_exists' using errcode='23505'; end if;

  v_permission:=case when v_type='receipt' then 'cashbox.receipt' else 'cashbox.payment' end;
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,v_permission) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;

  if p_replace then
    v_old_type:=lower(btrim(coalesce(v_old->>'type','')));
    if v_old_type not in ('receipt','payment') then raise exception 'existing_cash_transaction_type_invalid' using errcode='22023'; end if;
    v_old_permission:=case when v_old_type='receipt' then 'cashbox.receipt' else 'cashbox.payment' end;
    if not public.is_company_admin(p_company_id)
       and not public.erp_cloud_user_has_permission(p_company_id,v_old_permission) then
      raise exception 'permission_denied:%',v_old_permission using errcode='42501';
    end if;
  end if;

  v_guarded:=public.erp_r24_guard_cash_transaction_payload(
    p_company_id,coalesce(v_old,'{}'::jsonb),p_transaction
  );
  perform public.erp_post_cloud_cash_transaction(p_company_id,v_guarded,p_replace);
end $$;

revoke all on function public.erp_r9_post_cloud_cash_transaction(uuid,jsonb,boolean) from public,anon;
grant execute on function public.erp_r9_post_cloud_cash_transaction(uuid,jsonb,boolean) to authenticated,service_role;


-- Direct Data API writes must not bypass the canonical cashbox invariants.
-- Legacy active rows were normalized earlier in this migration.
alter table public.erp_cash_accounts
  drop constraint if exists erp_cash_accounts_r49_required_state_chk;
alter table public.erp_cash_accounts
  add constraint erp_cash_accounts_r49_required_state_chk check (
    is_deleted
    or (
      (coalesce(data,'{}'::jsonb) ? 'isActive' or coalesce(data,'{}'::jsonb) ? 'is_active')
      and upper(btrim(coalesce(data->>'currency',''))) in ('USD','IQD')
      and nullif(btrim(coalesce(
        data->>'canonical',data->>'account_id',data->>'accountId',data->>'ledgerAccountId',''
      )), '') is not null
    )
  );

commit;
