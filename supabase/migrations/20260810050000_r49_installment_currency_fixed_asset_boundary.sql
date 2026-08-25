-- R49 autonomous completion: installment currency traceability and UI data boundary.
-- Forward-only. Historical migrations remain unchanged.
begin;

create or replace function public.erp_r49_list_installments(
  p_company_id uuid
) returns setof jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  r record;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'installments.view')
     and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:installments.view' using errcode='42501';
  end if;

  for r in
    select
      i.data || jsonb_build_object(
        'currencyCode', upper(coalesce(
          nullif(i.data->>'currencyCode',''),
          nullif(s.data->>'currencyCode',''),
          'USD'
        )),
        'saleId', coalesce(nullif(i.data->>'saleId',''), s.id)
      ) as payload
    from public.erp_installments i
    left join public.erp_sales s
      on s.company_id=i.company_id
     and s.id=i.data->>'saleId'
     and not s.is_deleted
    where i.company_id=p_company_id
      and not i.is_deleted
    order by public.erp_try_date(i.data->>'dueDate', current_date),
             public.erp_try_integer(i.data->>'installmentNo',0),
             i.id
  loop
    return next r.payload;
  end loop;
end
$$;


create or replace function public.erp_r49_installment_dashboard_summary(
  p_company_id uuid,
  p_reference_day date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_outstanding jsonb := '{}'::jsonb;
  v_upcoming jsonb := '[]'::jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.view')
     and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:dashboard.view' using errcode='42501';
  end if;

  with rows as (
    select
      upper(coalesce(
        nullif(i.data->>'currencyCode',''),
        nullif(s.data->>'currencyCode',''),
        'USD'
      )) as currency,
      public.erp_try_numeric(i.data->>'remainingAmount',0) as remaining
    from public.erp_installments i
    left join public.erp_sales s
      on s.company_id=i.company_id
     and s.id=i.data->>'saleId'
     and not s.is_deleted
    where i.company_id=p_company_id
      and not i.is_deleted
      and public.erp_try_numeric(i.data->>'remainingAmount',0)>0
  ), grouped as (
    select currency,sum(remaining) amount
    from rows
    group by currency
  )
  select coalesce(
    jsonb_object_agg(currency,amount) filter(where currency in ('USD','IQD')),
    '{}'::jsonb
  ) into v_outstanding
  from grouped;

  select coalesce(jsonb_agg(payload order by due_date, installment_no),'[]'::jsonb)
  into v_upcoming
  from (
    select
      jsonb_build_object(
        'customerName',coalesce(c.data->>'name','عميل'),
        'installmentNo',public.erp_try_integer(i.data->>'installmentNo',0),
        'dueDate',i.data->>'dueDate',
        'remainingAmount',public.erp_try_numeric(i.data->>'remainingAmount',0),
        'currencyCode',upper(coalesce(
          nullif(i.data->>'currencyCode',''),
          nullif(s.data->>'currencyCode',''),
          'USD'
        )),
        'isOverdue',public.erp_try_date(i.data->>'dueDate',p_reference_day)<p_reference_day
      ) as payload,
      public.erp_try_date(i.data->>'dueDate',p_reference_day) as due_date,
      public.erp_try_integer(i.data->>'installmentNo',0) as installment_no
    from public.erp_installments i
    left join public.erp_sales s
      on s.company_id=i.company_id
     and s.id=i.data->>'saleId'
     and not s.is_deleted
    left join public.erp_customers c
      on c.company_id=s.company_id
     and c.id=s.data->>'customerId'
     and not c.is_deleted
    where i.company_id=p_company_id
      and not i.is_deleted
      and public.erp_try_numeric(i.data->>'remainingAmount',0)>0
      and public.erp_try_date(i.data->>'dueDate',p_reference_day)<=p_reference_day+7
    order by due_date,installment_no,i.id
    limit 7
  ) q;

  return jsonb_build_object(
    'outstandingInstallmentsByCurrency',v_outstanding,
    'upcomingInstallments',v_upcoming
  );
end
$$;

create or replace function public.erp_r9_cloud_dashboard_snapshot(
  p_company_id uuid,
  p_reference_day date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_raw jsonb;
  v_money jsonb;
  v_installments jsonb;
  v_result jsonb := '{}'::jsonb;
  v_item record;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.view')
     and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:dashboard.view' using errcode='42501';
  end if;

  v_raw := public.erp_cloud_dashboard_snapshot(p_company_id,p_reference_day)
    - 'outstandingInstallments'
    - 'upcomingInstallments';
  v_money := public.erp_r49_financial_summary_by_currency(p_company_id,p_reference_day);
  v_installments := public.erp_r49_installment_dashboard_summary(p_company_id,p_reference_day);
  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.fields.restrict') then
    return v_raw || v_money || v_installments;
  end if;

  for v_item in select key,value from jsonb_each(coalesce(v_raw,'{}'::jsonb)) loop
    if public.erp_cloud_user_can_view_field(
         p_company_id,'dashboard',v_item.key,'dashboard.view'
       ) then
      v_result := v_result || jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;

  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalSales','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalSalesByCurrency',v_money->'totalSalesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','todaySales','dashboard.view') then
    v_result:=v_result||jsonb_build_object('todaySalesByCurrency',v_money->'todaySalesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalPurchases','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalPurchasesByCurrency',v_money->'totalPurchasesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalExpenses','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalExpensesByCurrency',v_money->'totalExpensesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','netProfit','dashboard.view') then
    v_result:=v_result||jsonb_build_object('netProfitByCurrency',v_money->'netProfitByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','inventoryValue','dashboard.view') then
    v_result:=v_result||jsonb_build_object('inventoryValueByCurrency',v_money->'inventoryValueByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalReceivables','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalReceivablesByCurrency',v_money->'totalReceivablesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalPayables','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalPayablesByCurrency',v_money->'totalPayablesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','outstandingInstallments','dashboard.view') then
    v_result:=v_result||jsonb_build_object('outstandingInstallmentsByCurrency',v_installments->'outstandingInstallmentsByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','upcomingInstallments','dashboard.view') then
    v_result:=v_result||jsonb_build_object('upcomingInstallments',v_installments->'upcomingInstallments');
  end if;
  return v_result;
end;
$$;

revoke all on function public.erp_r49_list_installments(uuid) from public,anon;
revoke all on function public.erp_r49_installment_dashboard_summary(uuid,date) from public,anon;
revoke all on function public.erp_r9_cloud_dashboard_snapshot(uuid,date) from public,anon;
grant execute on function public.erp_r49_list_installments(uuid) to authenticated,service_role;
grant execute on function public.erp_r49_installment_dashboard_summary(uuid,date) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_dashboard_snapshot(uuid,date) to authenticated,service_role;

select pg_notify('pgrst','reload schema');
commit;
