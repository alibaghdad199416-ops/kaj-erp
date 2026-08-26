-- Deterministic post-migration seed contract.
-- Core tenant/master rows are created by the enterprise foundation migration.
-- This file is intentionally idempotent and only verifies that the required
-- bootstrap contract exists; it does not create demo/business transactions.

begin;

do $$
begin
  if not exists (
    select 1
    from public.companies
    where id = '11111111-1111-4111-8111-111111111111'::uuid
      and slug = 'quality-line'
  ) then
    raise exception 'seed contract: canonical Quality Line company is missing';
  end if;

  if not exists (
    select 1
    from public.branches
    where id = '22222222-2222-4222-8222-222222222222'::uuid
      and company_id = '11111111-1111-4111-8111-111111111111'::uuid
      and code = 'MAIN'
  ) then
    raise exception 'seed contract: canonical MAIN branch is missing';
  end if;

  if not exists (select 1 from public.currencies where code = 'IQD') then
    raise exception 'seed contract: IQD currency is missing';
  end if;

  if not exists (select 1 from public.currencies where code = 'USD') then
    raise exception 'seed contract: USD currency is missing';
  end if;
end $$;

commit;
