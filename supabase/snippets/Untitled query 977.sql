do $$
declare v_user_id uuid;
begin
  select id into v_user_id from auth.users where email = 'admin@kaj.com';
  
  if v_user_id is null then
    raise exception 'اليوزر admin@kaj.com مش موجود. اعمله من Authentication';
  end if;

  -- 1. اعمل الشركة بالاعمدة الصح
  insert into public.companies (id, slug, name_ar, name_en, default_currency_code, is_active, created_at)
  values ('00000-0000-0000-0000-000001', 'kaj-motors', 'كاج موتورز', 'KAJ Motors', 'IQD', true, now())
  on conflict (id) do update set 
    name_ar = 'كاج موتورز', 
    name_en = 'KAJ Motors';

  -- 2. اربط اليوزر بالشركة
  insert into public.company_memberships (company_id,