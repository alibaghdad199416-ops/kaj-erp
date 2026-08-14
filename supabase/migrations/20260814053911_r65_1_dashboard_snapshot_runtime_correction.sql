-- R65.1: correct two defects found by the first authenticated local runtime
-- call. Keep R65 immutable and replace only its exact known source fragments.
begin;

do $migration$
declare
  v_definition text;
  v_next text;
begin
  select pg_get_functiondef(
    'public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)'::regprocedure
  ) into v_definition;

  v_next:=replace(v_definition,
$old$    select a.currency from public.erp_accounts a
    where a.organization_id=p_company_id and a.is_active
      and a.account_type in ('revenue','expense')$old$,
$new$    select a.currency
    from public.erp_journal_lines jl
    join public.erp_journal_entries je on je.company_id=jl.company_id
      and je.id=jl.data->>'entryId' and not je.is_deleted and je.data->>'status'='posted'
    join public.erp_accounts a on a.organization_id=jl.company_id
      and a.account_id=jl.data->>'accountId' and a.is_active
    where jl.company_id=p_company_id and not jl.is_deleted
      and a.account_type in ('revenue','expense')
      and (v_from is null or coalesce(public.erp_try_date(je.data->>'entryDate',null),je.created_at::date)>=v_from)
      and coalesce(public.erp_try_date(je.data->>'entryDate',null),je.created_at::date)<=v_to$new$);
  if v_next=v_definition then
    raise exception 'r65_1_currency_validation_source_fragment_not_found';
  end if;
  v_definition:=v_next;

  v_next:=replace(v_definition,
$old$  from currencies c
  left join sales s using(currency) left join purchases p using(currency)
  left join maintenance m using(currency) left join maintenance_cost mc using(currency)
  left join inventory i using(currency) left join cash ch using(currency)
  left join advances ca on ca.currency=c.currency and ca.party_type='customer'
  left join advances sa on sa.currency=c.currency and sa.party_type='supplier'
  left join pnl pl using(currency);$old$,
$new$  from currencies c
  left join sales s on s.currency=c.currency
  left join purchases p on p.currency=c.currency
  left join maintenance m on m.currency=c.currency
  left join maintenance_cost mc on mc.currency=c.currency
  left join inventory i on i.currency=c.currency
  left join cash ch on ch.currency=c.currency
  left join advances ca on ca.currency=c.currency and ca.party_type='customer'
  left join advances sa on sa.currency=c.currency and sa.party_type='supplier'
  left join pnl pl on pl.currency=c.currency;$new$);
  if v_next=v_definition then
    raise exception 'r65_1_currency_join_source_fragment_not_found';
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
