insert into public.company_memberships (company_id, user_id, role, created_at)
values ('00000-0000-0000-0000-000001', 'PASTE_USER_ID_HERE', 'admin', now())
on conflict (company_id, user_id) do update set role = 'admin';