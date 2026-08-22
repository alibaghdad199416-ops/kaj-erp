begin;

do $$
declare
  v_user_id uuid := 'cdd35868-783d-4338-a418-0a8597503931';
  v_membership_id uuid := '9da768ab-4c60-4489-980b-4d239c8a6073';
  v_email text := 'ajkinbaghdad@gmail.com';
begin
  -- تأكد أن مستخدم Supabase Auth موجود فعلاً.
  if not exists (
    select 1
    from auth.users
    where id = v_user_id
      and lower(email) = lower(v_email)
  ) then
    raise exception 'Expected Supabase Auth user was not found';
  end if;

  -- أنشئ/فعّل Profile لنفس مستخدم Auth.
  insert into public.profiles(
    id,
    full_name,
    is_active,
    updated_at
  )
  values (
    v_user_id,
    split_part(v_email, '@', 1),
    true,
    now()
  )
  on conflict (id) do update
  set
    full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
    is_active = true,
    updated_at = now();

  -- أعد ربط العضوية القديمة نفسها بهوية Supabase الجديدة.
  update public.company_memberships
  set
    user_id = v_user_id,
    user_uid = v_user_id::text,
    user_email = lower(v_email),
    local_user_id = 'quality-line-owner',
    default_branch_id = '22222222-2222-4222-8222-222222222222',
    role_code = 'owner',
    is_system_admin = true,
    is_active = true,
    updated_at = now()
  where id = v_membership_id
    and company_id = '11111111-1111-4111-8111-111111111111'
    and lower(user_email) = lower(v_email);

  if not found then
    raise exception 'Legacy company membership was not found';
  end if;

  -- أغلق سجل مشكلة التحويل إن كان موجوداً.
  update public.supabase_identity_migration_issues
  set resolved_at = now()
  where membership_id = v_membership_id;
end
$$;

commit;