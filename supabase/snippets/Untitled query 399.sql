-- 1. نتاكد ان اليوزر موجود
do $$
declare v_user_id uuid;
begin
  select id into v_user_id from auth.users where email = 'admin@kaj.com';
  
  if v_user_id is null then
    raise exception 'اليوزر admin@kaj.com مش موجود. اعمله من Authentication اول';
  end if;

  -- 2. اعمل الشركة
  insert into public.companies (id, name, slug, base_currency, created_at)
  values ('00000000-0000-0000-0000-000001', 'KAJ Motors', 'kaj-motors', 'IQD', now())
  on conflict (id) do update set name = 'KAJ Motors';

  -- 3. اربط اليوزر بالشركة
  insert into public.company_members (company_id, user_id, role, created_at)
  values ('00000000-0000-0000-0000-000000000001', v_user_id, 'admin', now())
  on conflict (company_id, user_id) do update set role = 'admin';

  raise notice 'تم انشاء الشركة وربط اليوزر بنجاح';
end $$;