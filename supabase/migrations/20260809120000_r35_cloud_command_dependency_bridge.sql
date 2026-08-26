begin;

-- Compatibility bridge required before R37.
-- R35's final implementation is applied later in the migration chain.
create or replace function public.erp_r35_cloud_command(
    p_area text,
    p_action text,
    p_payload jsonb
) returns jsonb
language sql
security definer
set search_path = public
as $$
    select public.erp_r27_cloud_command(
        $1,
        $2,
        coalesce($3, '{}'::jsonb)
    )
$$;

revoke all on function public.erp_r35_cloud_command(text,text,jsonb)
    from public, anon;

grant execute on function public.erp_r35_cloud_command(text,text,jsonb)
    to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
