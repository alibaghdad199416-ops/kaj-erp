begin;

-- Keep the client capability check aligned with the modular Flutter runtime.
-- The function is read-only and intentionally checks table existence only;
-- RLS and tenant membership remain enforced by the actual module RPCs.
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
    'dashboard', to_regclass('public.erp_cars') is not null
      and to_regclass('public.erp_sales') is not null,
    'search', to_regclass('public.erp_cars') is not null
      and to_regclass('public.erp_customers') is not null,
    'notifications', to_regclass('public.erp_enterprise_notifications') is not null,
    'cars', to_regclass('public.erp_cars') is not null,
    'customers', to_regclass('public.erp_customers') is not null,
    'suppliers', to_regclass('public.erp_suppliers') is not null,
    'customer_service', to_regclass('public.erp_service_cases') is not null,
    'sales', to_regclass('public.erp_sales') is not null,
    'purchases', to_regclass('public.erp_purchases') is not null
      and to_regclass('public.erp_purchase_items') is not null,
    'installments', to_regclass('public.erp_installments') is not null,
    'inventory', to_regclass('public.erp_inventory') is not null
      and to_regclass('public.erp_warehouse_stock') is not null,
    'maintenance', to_regclass('public.erp_maintenance_orders') is not null
      and to_regclass('public.erp_maintenance_parts') is not null
      and to_regclass('public.erp_maintenance_payments') is not null,
    'accounting', to_regclass('public.erp_accounts') is not null
      and to_regclass('public.erp_journal_entries') is not null
      and to_regclass('public.erp_journal_lines') is not null,
    'cashbox', to_regclass('public.erp_cash_transactions') is not null,
    'expenses', to_regclass('public.erp_expenses') is not null,
    'reports', to_regclass('public.erp_saved_report_filters') is not null,
    'settings', to_regclass('public.erp_user_ui_preferences') is not null,
    'access', to_regclass('public.erp_permission_roles') is not null
      and to_regclass('public.erp_role_permission_grants') is not null
      and to_regclass('public.erp_user_role_assignments') is not null,
    'documents', to_regclass('public.erp_document_records') is not null
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
