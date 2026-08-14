-- R65.3: preserve the established top-level field-permission contract while
-- projecting every authoritative R65 measure, including typed count fields.
begin;
do $migration$
declare v_definition text; v_next text;
begin
  select pg_get_functiondef(
    'public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)'::regprocedure
  ) into v_definition;

  v_next:=replace(v_definition,
$old$  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.fields.restrict') then
    return v_result;
  end if;
  v_result:='{}'::jsonb;
  for v_item in select key,value from jsonb_each(jsonb_build_object(
    'filter',jsonb_build_object('fromDate',v_from,'toDate',v_to,'timezone','Asia/Baghdad'),
    'financial',v_financial,'statusCounts',v_status,'salesTrend',v_trend,
    'recentDocuments',v_recent,'generatedAt',clock_timestamp()
  )) loop
    if public.erp_cloud_user_can_view_field(p_company_id,'dashboard',v_item.key,'dashboard.view') then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;$old$,
$new$  v_result:=(v_result-'financial')||jsonb_build_object(
    'totalSalesByCurrency',v_financial->'salesInvoicesByCurrency',
    'todaySalesByCurrency',v_financial->'todaySalesInvoicesByCurrency',
    'salesCollectionsByCurrency',v_financial->'salesCollectionsByCurrency',
    'totalPurchasesByCurrency',v_financial->'purchaseInvoicesByCurrency',
    'purchasePaymentsByCurrency',v_financial->'purchasePaymentsByCurrency',
    'maintenanceRevenueByCurrency',v_financial->'maintenanceRevenueByCurrency',
    'maintenancePaidByCurrency',v_financial->'maintenancePaidByCurrency',
    'maintenanceOutstandingByCurrency',v_financial->'maintenanceOutstandingByCurrency',
    'maintenanceActualCostByCurrency',v_financial->'maintenanceActualCostByCurrency',
    'totalReceivablesByCurrency',v_financial->'receivablesByCurrency',
    'totalPayablesByCurrency',v_financial->'payablesByCurrency',
    'customerAdvancesByCurrency',v_financial->'customerAdvancesByCurrency',
    'supplierAdvancesByCurrency',v_financial->'supplierAdvancesByCurrency',
    'cashBalanceByCurrency',v_financial->'cashByCurrency',
    'cashBalanceUsd',coalesce((v_financial->'cashByCurrency'->>'USD')::numeric,0),
    'cashBalanceIqd',coalesce((v_financial->'cashByCurrency'->>'IQD')::numeric,0),
    'inventoryValueByCurrency',v_financial->'inventoryValueByCurrency',
    'recognizedRevenueByCurrency',v_financial->'recognizedRevenueByCurrency',
    'totalExpensesByCurrency',v_financial->'recognizedExpenseByCurrency',
    'netProfitByCurrency',v_financial->'netProfitByCurrency'
  );
  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.fields.restrict') then
    return v_result;
  end if;
  v_financial:=v_result;
  v_result:='{}'::jsonb;
  for v_item in select key,value from jsonb_each(v_financial) loop
    if public.erp_cloud_user_can_view_field(
         p_company_id,'dashboard',v_item.key,'dashboard.view'
       ) then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;$new$);
  if v_next=v_definition then
    raise exception 'r65_3_field_projection_source_fragment_not_found';
  end if;
  execute v_next;
end;
$migration$;
revoke all on function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)
  from public,anon,authenticated;
grant execute on function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)
  to authenticated,service_role;
notify pgrst,'reload schema';
commit;
