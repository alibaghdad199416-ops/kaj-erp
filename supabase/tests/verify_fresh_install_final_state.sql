\set ON_ERROR_STOP on

do $verify$
declare
  v_definition text;
  v_source text;
  v_language text;
  v_security_definer boolean;
  v_config text[];
begin
  select pg_get_functiondef(p.oid),p.prosrc,l.lanname,p.prosecdef,p.proconfig
    into v_definition,v_source,v_language,v_security_definer,v_config
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  join pg_language l on l.oid=p.prolang
  where n.nspname='public'
    and p.oid='public.erp_r35_cloud_command(text,text,jsonb)'::regprocedure;

  if v_definition is null then raise exception 'canonical_r35_missing'; end if;
  if v_definition like '%fresh_install_r35_compatibility_must_not_execute%'
     or exists(
       select 1 from pg_proc
       where prosrc like '%fresh_install_r35_compatibility_must_not_execute%'
     ) then
    raise exception 'fresh_install_placeholder_survived';
  end if;
  if v_language<>'sql' or not v_security_definer then
    raise exception 'canonical_r35_execution_semantics_mismatch';
  end if;
  if v_config is distinct from array['search_path=public']::text[] then
    raise exception 'canonical_r35_search_path_mismatch:%',v_config;
  end if;
  if regexp_replace(v_source,'\s+','','g')
     <> 'selectpublic.erp_r27_cloud_command($1,$2,coalesce($3,''{}''::jsonb))' then
    raise exception 'canonical_r35_body_mismatch:%',v_source;
  end if;
  if has_function_privilege('anon','public.erp_r35_cloud_command(text,text,jsonb)','execute')
     or not has_function_privilege('authenticated','public.erp_r35_cloud_command(text,text,jsonb)','execute')
     or not has_function_privilege('service_role','public.erp_r35_cloud_command(text,text,jsonb)','execute') then
    raise exception 'canonical_r35_privileges_mismatch';
  end if;
end
$verify$;

select 'PASS fresh-install canonical R35 replacement' as result;
