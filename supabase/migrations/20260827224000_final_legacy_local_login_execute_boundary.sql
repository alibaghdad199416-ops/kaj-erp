begin;

-- Final security closure for the historical local-login bootstrap RPC.
-- Anonymous browser sessions must not be able to invoke the legacy bootstrap.
revoke all on function public.authenticate_local_erp_user(text,text,text) from public, anon;
grant execute on function public.authenticate_local_erp_user(text,text,text) to authenticated;

notify pgrst, 'reload schema';
commit;
