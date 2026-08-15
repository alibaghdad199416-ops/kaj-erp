begin;

-- R74: authenticated runtime identity attestation.
--
-- The browser already pins the Supabase project URL. This RPC additionally
-- proves which Auth user and company tenant the current request is executing as,
-- so a stale browser company cache can never be mistaken for another tenant.
create or replace function public.erp_r74_runtime_identity(
  p_company_id uuid
) returns jsonb
language plpgsql
volatile
security definer
set search_path=public
as $$
declare
  v_user_id uuid:=auth.uid();
  v_company record;
begin
  if v_user_id is null then
    raise exception 'authentication_required' using errcode='42501';
  end if;

  perform public.erp_active_company_context(p_company_id);

  select c.id,c.slug,c.name_ar,c.name_en,c.is_active
  into v_company
  from public.companies as c
  where c.id=p_company_id
    and c.is_active
  limit 1;

  if not found then
    raise exception 'company_not_found_or_inactive' using errcode='42501';
  end if;

  return jsonb_build_object(
    'databaseContract','R74',
    'authUserId',v_user_id,
    'companyId',v_company.id,
    'companySlug',v_company.slug,
    'companyName',coalesce(v_company.name_ar,v_company.name_en,''),
    'serverTime',clock_timestamp()
  );
end;
$$;

revoke all on function public.erp_r74_runtime_identity(uuid)
  from public,anon,authenticated;
grant execute on function public.erp_r74_runtime_identity(uuid)
  to authenticated,service_role;

-- Reassert the private preferences contract used during authenticated startup.
-- These statements are non-destructive and make any drift explicit.
alter table public.erp_user_ui_preferences enable row level security;
alter table public.erp_user_ui_preferences force row level security;
grant select,insert,update,delete on public.erp_user_ui_preferences to authenticated;
revoke all on public.erp_user_ui_preferences from anon;

notify pgrst,'reload schema';
commit;
