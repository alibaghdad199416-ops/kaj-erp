do $$
declare v_user_id uuid;
begin
  select id into v_user_id from auth.users where email = 'admin@kaj.com';
  
  if v_user_id is null then
    raise exception 'اليوزر admin@kaj.com مش موجود. اعمله من Authentication';
  end if;

  -- 1. اعمل الشركة - غالبا اسم العمود display_name مش name
  insert into public.companies (id, slug, base_currency, display_name, created_at)
  values ('00000-0000-0000-0000-000001', 'kaj-motors', 'IQD', 'KAJ Motors', now())
  on conflict (id) do update set display_name = 'KAJ Motors';

  -- 2. اربط اليوزر بالشركة
  insert into public.company_memberships (company_id, user_id, role, created_at)
  values ('00000000-0000-0000-0000-000001', v_user_id, 'admin', now())
  on conflict (company_id, user_id) do update set role = 'admin';

  raise notice 'تم انشاء الشركة وربط اليوزر بنجاح';
end $$;