begin;

-- Phase 2 security boundary: ERP state changes must flow through controlled
-- RPC/SECURITY DEFINER command surfaces, not arbitrary PostgREST table DML.
-- Keep read access governed by RLS/policies; remove client INSERT/UPDATE/DELETE
-- privileges from all public-schema tables. service_role/database owners remain
-- unaffected and SECURITY DEFINER functions retain their owner privileges.
do $$
declare
  r record;
begin
  for r in
    select format('%I.%I', n.nspname, c.relname) as qualified_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r','p')
  loop
    execute format('revoke insert, update, delete on table %s from public, anon, authenticated', r.qualified_name);
  end loop;
end;
$$;

commit;
