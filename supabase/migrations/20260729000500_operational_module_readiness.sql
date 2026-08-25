begin;

create or replace function public.erp_operational_readiness(
  p_company_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_firebase_uid text := public.erp_current_firebase_uid();
  v_is_member boolean := false;
  v_modules jsonb;
begin
  if p_company_id is null then
    raise exception 'company_id_required' using errcode = '22023';
  end if;

  select exists (
    select 1
    from public.company_memberships membership
    where membership.company_id = p_company_id
      and membership.user_uid = v_firebase_uid
      and membership.is_active = true
  )
  into v_is_member;

  if not v_is_member then
    raise exception 'company_membership_required' using errcode = '42501';
  end if;

  v_modules := jsonb_build_object(
    'cars', to_regclass('public.erp_cars') is not null,
    'customers', to_regclass('public.erp_customers') is not null,
    'suppliers', to_regclass('public.erp_suppliers') is not null,
    'sales', to_regclass('public.erp_sales') is not null,
    'purchases', to_regclass('public.erp_purchases') is not null
      and to_regclass('public.erp_purchase_items') is not null,
    'installments', to_regclass('public.erp_installments') is not null,
    'inventory', to_regclass('public.erp_inventory') is not null
      and to_regclass('public.erp_warehouse_stock') is not null,
    'accounting', to_regclass('public.erp_accounts') is not null
      and to_regclass('public.erp_journal_entries') is not null,
    'cashbox', to_regclass('public.erp_cash_transactions') is not null,
    'documents', to_regclass('public.erp_documents') is not null
  );

  return jsonb_build_object(
    'ok', not exists (
      select 1 from jsonb_each(v_modules) item where item.value <> 'true'::jsonb
    ),
    'company_id', p_company_id,
    'firebase_uid', v_firebase_uid,
    'modules', v_modules,
    'checked_at', timezone('utc', now())
  );
end;
$$;

revoke all on function public.erp_operational_readiness(uuid) from public;
grant execute on function public.erp_operational_readiness(uuid) to authenticated;

commit;
