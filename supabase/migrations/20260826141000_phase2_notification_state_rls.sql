begin;

-- Notification delivery state is server-maintained. Client roles must never
-- mutate or read it directly; the explicit deny policy documents that contract
-- while SECURITY DEFINER/service-role code remains able to maintain the state.
alter table public.erp_notification_user_states enable row level security;
drop policy if exists erp_notification_user_states_client_deny on public.erp_notification_user_states;
create policy erp_notification_user_states_client_deny
  on public.erp_notification_user_states
  for all to anon, authenticated
  using (false)
  with check (false);
revoke all on public.erp_notification_user_states from public, anon, authenticated;

commit;
