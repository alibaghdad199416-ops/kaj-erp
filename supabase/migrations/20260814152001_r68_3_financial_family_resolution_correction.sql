begin;

do $$
declare
  v_definition text;
  v_corrected text;
begin
  select pg_get_functiondef(
    'public.erp_r68_delete_financial_transaction_family(uuid,text,text)'::regprocedure
  ) into v_definition;
  v_corrected:=replace(
    v_definition,
    'coalesce(v_family,p.value->>''paymentKey'',p.value->>''paymentId'',v_seed.id)',
    'coalesce(v_family,max(p.value->>''paymentKey''),max(p.value->>''paymentId''),v_seed.id)'
  );
  v_corrected:=replace(
    v_corrected,
    'coalesce(v_payment,p.value->>''paymentId'')',
    'coalesce(v_payment,max(p.value->>''paymentId''))'
  );
  v_corrected:=replace(
    v_corrected,
    'coalesce(v_key,p.value->>''paymentKey'')',
    'coalesce(v_key,max(p.value->>''paymentKey''))'
  );
  v_corrected:=replace(
    v_corrected,
    'coalesce(v_transfer,p.value->>''transferId'')',
    'coalesce(v_transfer,max(p.value->>''transferId''))'
  );
  if v_corrected=v_definition then
    raise exception 'r68_family_resolution_patch_target_not_found';
  end if;
  execute v_corrected;
end;
$$;

notify pgrst,'reload schema';
commit;
