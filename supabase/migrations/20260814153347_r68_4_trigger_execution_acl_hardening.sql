begin;

revoke all on function public.erp_r68_stamp_document_payment_families()
  from public,anon,authenticated;
revoke all on function public.erp_r68_stamp_maintenance_payment_family()
  from public,anon,authenticated;

commit;
