-- Quality Line ERP v15.93.0
-- Adds server-side throttling for anonymous ERP username/password bootstrap.
create table if not exists public.erp_login_attempts (
  company_id text not null,
  username_key text not null,
  window_started_at timestamptz not null default now(),
  attempt_count integer not null default 0,
  locked_until timestamptz,
  primary key (company_id, username_key)
);

alter table public.erp_login_attempts enable row level security;
revoke all on public.erp_login_attempts from anon, authenticated;

create or replace function public.authenticate_local_erp_user(
  p_company_id text,
  p_username text,
  p_password_hash text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user jsonb;
  v_role jsonb;
  v_permissions jsonb;
  v_role_permissions jsonb;
  v_role_id text;
  v_key text := lower(trim(p_username));
  v_attempt public.erp_login_attempts%rowtype;
begin
  if coalesce(trim(p_company_id), '') = ''
     or coalesce(v_key, '') = ''
     or p_password_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  insert into public.erp_login_attempts(company_id, username_key, attempt_count)
  values (p_company_id, v_key, 0)
  on conflict (company_id, username_key) do nothing;

  select * into v_attempt from public.erp_login_attempts
  where company_id = p_company_id and username_key = v_key
  for update;

  if v_attempt.locked_until is not null and v_attempt.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked');
  end if;

  if v_attempt.window_started_at < now() - interval '15 minutes' then
    update public.erp_login_attempts set window_started_at = now(), attempt_count = 0,
      locked_until = null where company_id = p_company_id and username_key = v_key;
    v_attempt.attempt_count := 0;
  end if;

  select r.payload into v_user from public.erp_records r
  where r.company_id = p_company_id and r.entity_type = 'users'
    and r.deleted_at is null and lower(r.payload->>'username') = v_key
    and r.payload->>'passwordHash' = p_password_hash
    and coalesce((r.payload->>'isActive')::int, 0) = 1 limit 1;

  if v_user is null then
    update public.erp_login_attempts
      set attempt_count = attempt_count + 1,
          locked_until = case when attempt_count + 1 >= 8 then now() + interval '15 minutes' else null end
      where company_id = p_company_id and username_key = v_key;
    perform pg_sleep(0.45);
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  update public.erp_login_attempts set attempt_count = 0, window_started_at = now(), locked_until = null
  where company_id = p_company_id and username_key = v_key;

  v_role_id := v_user->>'roleId';
  select r.payload into v_role from public.erp_records r
  where r.company_id = p_company_id and r.entity_type = 'roles'
    and r.record_id = v_role_id and r.deleted_at is null
    and coalesce((r.payload->>'isActive')::int, 0) = 1 limit 1;
  if v_role is null then return jsonb_build_object('ok', false, 'reason', 'inactive_role'); end if;

  select coalesce(jsonb_agg(r.payload), '[]'::jsonb) into v_role_permissions
  from public.erp_records r where r.company_id = p_company_id
    and r.entity_type = 'role_permissions' and r.deleted_at is null
    and r.payload->>'roleId' = v_role_id;

  select coalesce(jsonb_agg(r.payload), '[]'::jsonb) into v_permissions
  from public.erp_records r where r.company_id = p_company_id
    and r.entity_type = 'permissions' and r.deleted_at is null and exists (
      select 1 from jsonb_array_elements(v_role_permissions) rp
      where rp->>'permissionId' = r.record_id or rp->>'permissionCode' = r.payload->>'code');

  return jsonb_build_object('ok', true, 'user', v_user, 'role', v_role,
    'permissions', v_permissions, 'role_permissions', v_role_permissions);
end;
$$;

revoke all on function public.authenticate_local_erp_user(text,text,text) from public;
grant execute on function public.authenticate_local_erp_user(text,text,text) to anon, authenticated;
