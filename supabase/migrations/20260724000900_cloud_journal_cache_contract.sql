-- P10: cloud journal is authoritative; clients may only read it through RLS.
-- Reporting projections are populated from these authoritative cloud journal rows.
comment on table public.erp_cloud_journal_entries is
  'Authoritative financial journal stored and queried in PostgreSQL.';
comment on table public.erp_cloud_journal_lines is
  'Authoritative financial journal lines. Client-side copies must not be recalculated.';
