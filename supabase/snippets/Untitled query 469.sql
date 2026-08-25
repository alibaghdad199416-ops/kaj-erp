insert into public.company_memberships 
(company_id, user_id, role_code, is_system_admin, is_active, created_at, user_email)
values 
('00000000-0000-0000-0000-000000000001', 'b1fca525-d392-46b9-a153-469d1d4a354e', 'admin', true, true, now(), 'admin@kaj.com')
on conflict (company_id, user_id) do update set 
  role_code = 'admin', 
  is_system_admin = true, 
  is_active = true;