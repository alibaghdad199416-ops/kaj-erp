insert into public.companies (id, slug, name_ar, name_en, default_currency_code, is_active, created_at)
values ('00000-0000-0000-0000-000001', 'kaj-motors', 'كاج موتورز', 'KAJ Motors', 'IQD', true, now())
on conflict (id) do update set 
  name_ar = 'كاج موتورز', 
  name_en = 'KAJ Motors';