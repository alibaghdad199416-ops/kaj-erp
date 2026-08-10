-- V8.0.0: persist a localized-independent job title in cloud user records.
-- erp_records stores record payloads as JSONB; this migration normalizes the
-- field for existing user records so application snapshots always receive it.

update public.erp_records
set payload = jsonb_set(
      coalesce(payload, '{}'::jsonb),
      '{jobTitle}',
      '""'::jsonb,
      true
    ),
    updated_at = now()
where entity_type = 'users'
  and not (coalesce(payload, '{}'::jsonb) ? 'jobTitle');