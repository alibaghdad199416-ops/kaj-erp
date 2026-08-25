-- اعمل شركة
insert into public.companies (id, name, slug, base_currency) 
values ('00000-0000-0000-0000-000001', 'KAJ Motors', 'kaj', 'IQD')
on conflict (id) do nothing;

-- اربط اليوزر admin@kaj.com بالشركة
insert into public.company_members (company_id, user_id, role)
select '00000000-0000-0000-0000-000000001', id, 'admin' 
from auth.users where email = 'admin@kaj.com'
on conflict (company_id, user_id) do nothing;