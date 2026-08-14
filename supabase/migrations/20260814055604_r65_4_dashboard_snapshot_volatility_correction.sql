-- R65.4: the snapshot emits clock_timestamp() and evaluates live request
-- context, so VOLATILE is the accurate PostgreSQL declaration. All reads still
-- execute in one statement and therefore retain one MVCC statement snapshot.
begin;
alter function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)
  volatile;
notify pgrst,'reload schema';
commit;
