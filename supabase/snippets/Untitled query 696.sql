do $$
declare 
  v_user_id uuid := 'b1fca525-d392-46b9-a153-469d1d4a354e';
  v_company_id uuid;
begin
  -- 1. اعمل الشركة وخليه هو يولد id
  insert into public.companies (slug, name_ar, name_en, default_currency_code, is_active, created_at)
  values ('kaj-motors', 'كاج موتورز', 'KAJ Motors', 'IQD', true, now())
  returning id into v_company_id;

  -- 2. اربط اليوزر بالشركة بنفس id اللي اتولد
  insert into public.company_memberships 
  (company_id, user_id, role_code, is_system_admin, is_active, created_at, user_email)
  values 
  (v_company_id, v_user_id, 'admin', true, true, now(), 'admin@kaj.com')
  on conflict (company_id, user_id) do update set 
    role_code = 'admin', 
    is_system_admin = true, 
    is_active = true;

  raise notice 'تم انشاء الشركة id=% وربط اليوزر', v_company_id;
end $$;