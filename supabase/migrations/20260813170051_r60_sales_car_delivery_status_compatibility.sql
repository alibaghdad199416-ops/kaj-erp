begin;

-- R59 accidentally dropped the canonical Arabic pending-sale label from the
-- delivery allocation validator. Approved sales orders intentionally move an
-- exact vehicle to this state before its physical delivery.
do $$
declare v_definition text; v_old text; v_new text;
begin
  select pg_get_functiondef(
    'public.erp_validate_commercial_warehouse_allocations(uuid,uuid,text,jsonb,boolean)'::regprocedure
  ) into v_definition;
  v_old:='(''available'',''selling'',''pending_sale'',''متوفرة'',''متوفر'',''متاح'')';
  v_new:='(''available'',''selling'',''pending_sale'',''متوفرة'',''متوفر'',''متاحة'',''متاح'',''قيد البيع'')';
  if strpos(v_definition,v_old)=0 then
    raise exception 'r60_expected_r59_car_status_guard_not_found';
  end if;
  execute replace(v_definition,v_old,v_new);
end $$;

commit;
