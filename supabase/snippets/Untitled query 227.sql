insert into public.company_memberships (company_id, user_id, created_at)
values ('00000000-0000-0000-0000-000000000001', 'b1fca525-d392-46b9-a153-469d1d4a354e', now())
on conflict (company_id, user_id) do nothing;