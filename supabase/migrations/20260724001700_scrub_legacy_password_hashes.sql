-- Remove obsolete local password hashes after Supabase Auth became authoritative.
begin;

update public.erp_records
set payload = jsonb_set(payload, '{passwordHash}', '""'::jsonb, true),
    updated_at = now()
where entity_type = 'users'
  and coalesce(payload->>'passwordHash', '') <> '';

commit;
