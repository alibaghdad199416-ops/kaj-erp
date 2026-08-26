begin;

-- Forward-only lint repair for the cloud invoice approval RPC.
-- Do not edit the applied historical migration. Recreate the function from
-- PostgreSQL's canonical definition while removing the unused local variable.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'erp_approve_invoice_cloud'
    and pg_get_function_identity_arguments(p.oid) = 'p_command_id uuid, p_invoice_id text';

  if v_definition is null then
    raise exception 'erp_approve_invoice_cloud_not_found';
  end if;

  v_definition := replace(v_definition, E'  v_partner_type text;\n', '');
  v_definition := replace(v_definition, E'    v_partner_type := ''customer'';\n', '');
  v_definition := replace(v_definition, E'    v_partner_type := ''supplier'';\n', '');

  if position('v_partner_type' in v_definition) > 0 then
    raise exception 'unused_partner_type_cleanup_incomplete';
  end if;

  execute v_definition;
end $$;

commit;
