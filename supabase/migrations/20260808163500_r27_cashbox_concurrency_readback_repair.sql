begin;
create or replace function public.erp_r27_list_cash_accounts(p_company_id uuid)
returns setof jsonb
language sql stable security definer set search_path=public
as $$
  select ca.data
    || jsonb_build_object(
      'id',ca.id,
      'accountId',public.erp_r23_cashbox_ledger_account_id(ca.data),
      'account_id',public.erp_r23_cashbox_ledger_account_id(ca.data),
      'updatedAt',ca.updated_at,
      'updated_at',ca.updated_at,
      '_cloudCreatedAt',ca.created_at,
      '_cloudUpdatedAt',ca.updated_at,
      '_cloudVersion',ca.version,
      'ledgerAccountCode',a.code,
      'ledgerAccountName',a.name,
      'ledgerAccountCurrency',a.currency
    )
  from public.erp_cash_accounts ca
  left join public.erp_accounts a
    on a.organization_id=ca.company_id
   and a.account_id=public.erp_r23_cashbox_ledger_account_id(ca.data)
  where ca.company_id=p_company_id
    and not ca.is_deleted
    and public.erp_is_company_member(p_company_id)
  order by public.erp_try_boolean(coalesce(ca.data->>'isActive',ca.data->>'is_active'),'true') desc,
           lower(coalesce(ca.data->>'name','')),ca.id
$$;
revoke all on function public.erp_r27_list_cash_accounts(uuid) from public,anon;
grant execute on function public.erp_r27_list_cash_accounts(uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
