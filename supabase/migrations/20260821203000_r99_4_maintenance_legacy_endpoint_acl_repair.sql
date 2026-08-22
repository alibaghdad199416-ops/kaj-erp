-- Quality Line ERP / KAJ ERP R99.4
-- R98 rebuilt record-scoped maintenance readers but accidentally re-exposed
-- the retired R88 implementations. Keep the R90 filtered wrappers as the only
-- authenticated browser boundary.
begin;

revoke all on function public.erp_r88_list_maintenance_payments(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.erp_r88_vehicle_service_card(uuid,text)
  from public,anon,authenticated;

grant execute on function public.erp_r88_list_maintenance_payments(uuid,uuid)
  to service_role;
grant execute on function public.erp_r88_vehicle_service_card(uuid,text)
  to service_role;

notify pgrst,'reload schema';
commit;
