do $$
declare
  v_user_id uuid := 'cdd35868-783d-4338-a418-0a8597503931'; -- Auth user UUID
  v_email text := 'ajkinbaghdad@gmail.com';                        -- Auth user email
  v_local_user_id text := 'quality-line-owner';               -- Stable ERP user id
begin
  if v_user_id = '00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'Replace v_user_id with the first Supabase Auth user UUID';
  end if;
  if v_email = 'owner@example.com' then
    raise exception 'Replace v_email with the first Supabase Auth user email';
  end if;

  if not exists (select 1 from auth.users where id = v_user_id) then
    raise exception 'Auth user % does not exist', v_user_id;
  end if;

  insert into public.profiles(id, full_name, is_active, updated_at)
  values (v_user_id, split_part(v_email, '@', 1), true, now())
  on conflict (id) do update
  set is_active = true,
      updated_at = now();

  insert into public.company_memberships(
    company_id,
    user_id,
    user_uid,
    user_email,
    local_user_id,
    default_branch_id,
    role_code,
    is_system_admin,
    is_active,
    updated_at
  ) values (
    '11111111-1111-4111-8111-111111111111',
    v_user_id,
    v_user_id::text,
    lower(v_email),
    v_local_user_id,
    '22222222-2222-4222-8222-222222222222',
    'owner',
    true,
    true,
    now()
  )
  on conflict (company_id, user_id) do update
  set user_uid = excluded.user_uid,
      user_email = excluded.user_email,
      local_user_id = excluded.local_user_id,
      default_branch_id = excluded.default_branch_id,
      role_code = 'owner',
      is_system_admin = true,
      is_active = true,
      updated_at = now();
end
$$;