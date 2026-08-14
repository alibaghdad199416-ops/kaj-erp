begin;

-- R37 is historically ordered before the canonical R35 migration even though
-- its SQL wrapper resolves this signature at CREATE FUNCTION time. Preserve
-- applied history and make the authoritative migration stream self-contained:
-- create a fail-closed parser dependency only when the function is absent.
-- Existing/upgraded databases already holding the canonical function are a
-- strict no-op; 20260809153000 replaces this placeholder during fresh replay.
do $bootstrap$
begin
  if to_regprocedure('public.erp_r35_cloud_command(text,text,jsonb)') is null then
    execute $function$
      create function public.erp_r35_cloud_command(
        p_area text,
        p_action text,
        p_payload jsonb
      ) returns jsonb
      language plpgsql
      security invoker
      set search_path=public
      as $body$
      begin
        raise exception 'fresh_install_r35_compatibility_must_not_execute'
          using errcode='55000';
      end;
      $body$
    $function$;
    revoke all on function public.erp_r35_cloud_command(text,text,jsonb)
      from public,anon,authenticated,service_role;
  end if;
end
$bootstrap$;

commit;
