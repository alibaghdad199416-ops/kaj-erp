-- R24 partner ledger closure: all workflows resolve customer/supplier USD/IQD ledgers
-- through the canonical partner-account resolver instead of legacy JSON aliases.
begin;

create or replace function public.erp_v764_assert_partner_dual_ledgers(
  p_company_id uuid,
  p_partner_id text,
  p_partner_type text
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_type text:=lower(btrim(coalesce(p_partner_type,'')));
  v_usd_id text;
  v_iqd_id text;
  v_expected_type text;
begin
  if v_type not in ('customer','supplier') then
    raise exception 'partner_type_invalid:%',p_partner_type;
  end if;

  if v_type='customer' then
    perform 1 from public.erp_customers
      where company_id=p_company_id and id=p_partner_id and not is_deleted;
    if not found then raise exception 'partner_not_found:%',p_partner_id; end if;
    v_expected_type:='asset';
  else
    perform 1 from public.erp_suppliers
      where company_id=p_company_id and id=p_partner_id and not is_deleted;
    if not found then raise exception 'partner_not_found:%',p_partner_id; end if;
    v_expected_type:='liability';
  end if;

  v_usd_id:=public.erp_workflow_partner_account(p_company_id,v_type,p_partner_id,'USD');
  v_iqd_id:=public.erp_workflow_partner_account(p_company_id,v_type,p_partner_id,'IQD');
  perform public.erp_phase2_account_guard(p_company_id,v_usd_id,v_expected_type,'USD');
  perform public.erp_phase2_account_guard(p_company_id,v_iqd_id,v_expected_type,'IQD');
end;
$$;

notify pgrst,'reload schema';
commit;
