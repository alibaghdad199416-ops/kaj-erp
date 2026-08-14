-- R65.2: the canonical reservation table has a typed status column.
begin;
do $migration$
declare v_definition text; v_next text;
begin
  select pg_get_functiondef(
    'public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)'::regprocedure
  ) into v_definition;
  v_next:=replace(
    v_definition,
    $old$lower(data->>'status')='active'$old$,
    $new$lower(status)='active'$new$
  );
  if v_next=v_definition then
    raise exception 'r65_2_reservation_status_source_fragment_not_found';
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
