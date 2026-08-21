\set ON_ERROR_STOP on
\pset pager off

begin;

-- Force only the access predicates needed by this isolated report fixture.
-- ROLLBACK restores the production authorization functions.
create or replace function public.is_active_company_member(p_company_id uuid)
returns boolean
language sql stable security definer set search_path=public as $$
  select true
$$;

create or replace function public.erp_cloud_user_has_permission(
  p_company_id uuid,p_permission_code text
) returns boolean
language sql stable security definer set search_path=public as $$
  select false
$$;

create or replace function public.erp_cloud_user_can_view_field(
  p_company_id uuid,p_resource text,p_field text,p_base_permission text default null
) returns boolean
language sql stable security definer set search_path=public as $$
  select trim(coalesce(p_resource,''))='accounting'
     and trim(coalesce(p_field,''))='generalLedger'
$$;

set local session_replication_role=replica;

insert into public.erp_accounts(
  organization_id,account_id,code,name,account_type,currency,
  opening_balance,is_active
) values (
  'a1010000-0000-4000-8000-000000000001',
  'r101-cash','1100','R101 Cash','asset','USD',100,true
);

insert into public.erp_journal_entries(
  company_id,id,data,created_at
) values (
  'a1010000-0000-4000-8000-000000000001',
  'r101-entry',
  jsonb_build_object(
    'entryNumber','R101-JE-1',
    'entryDate','2026-08-21T10:00:00Z',
    'currency','USD',
    'status','posted'
  ),
  '2026-08-21T10:00:00Z'::timestamptz
);

-- Both lines intentionally share every timestamp. Only line_id can provide a
-- deterministic order; lexical line-a must precede line-b.
insert into public.erp_journal_lines(
  company_id,id,data,created_at
) values
(
  'a1010000-0000-4000-8000-000000000001',
  'line-a',
  jsonb_build_object(
    'id','line-a','entryId','r101-entry','accountId','r101-cash',
    'description','A debit','debit',10,'credit',0
  ),
  '2026-08-21T10:00:00Z'::timestamptz
),
(
  'a1010000-0000-4000-8000-000000000001',
  'line-b',
  jsonb_build_object(
    'id','line-b','entryId','r101-entry','accountId','r101-cash',
    'description','B credit','debit',0,'credit',3
  ),
  '2026-08-21T10:00:00Z'::timestamptz
);

set local session_replication_role=origin;

do $$
declare
  v_def text;
  v_row jsonb;
  v_index integer:=0;
  v_wrapper_rows integer:=0;
begin
  select pg_get_functiondef(
    'public.erp_r101_cloud_general_ledger(uuid,text,text,text,timestamptz,timestamptz)'::regprocedure
  ) into v_def;
  if v_def not like '%line.entry_id%'
     or v_def not like '%line.line_id%'
     or v_def not like '%sum(line.natural_delta) over%' then
    raise exception 'r101_stable_running_balance_order_not_installed';
  end if;

  for v_row in
    select * from public.erp_r101_cloud_general_ledger(
      'a1010000-0000-4000-8000-000000000001','USD',null,null,null,null
    )
  loop
    v_index:=v_index+1;
    if v_index=1 and (
      v_row->>'description'<>'A debit'
      or abs(coalesce((v_row->>'runningBalance')::numeric,0)-110)>0.000001
    ) then
      raise exception 'r101_first_running_balance_incorrect:%',v_row;
    elsif v_index=2 and (
      v_row->>'description'<>'B credit'
      or abs(coalesce((v_row->>'runningBalance')::numeric,0)-107)>0.000001
    ) then
      raise exception 'r101_second_running_balance_incorrect:%',v_row;
    end if;
  end loop;
  if v_index<>2 then
    raise exception 'r101_expected_two_gl_rows_got:%',v_index;
  end if;

  -- The browser-facing stable R22 RPC must route GL through R101 and return the
  -- same deterministic running balances.
  for v_row in
    select * from public.erp_r22_cloud_detailed_accounting_report(
      'a1010000-0000-4000-8000-000000000001',
      'generalLedger','USD',null,null,null,null
    )
  loop
    v_wrapper_rows:=v_wrapper_rows+1;
    if v_wrapper_rows=1 and (v_row->>'runningBalance')::numeric<>110 then
      raise exception 'r101_r22_first_running_balance_incorrect:%',v_row;
    elsif v_wrapper_rows=2 and (v_row->>'runningBalance')::numeric<>107 then
      raise exception 'r101_r22_second_running_balance_incorrect:%',v_row;
    end if;
  end loop;
  if v_wrapper_rows<>2 then
    raise exception 'r101_r22_expected_two_gl_rows_got:%',v_wrapper_rows;
  end if;
end $$;

rollback;
select 'R101 deterministic GL running balance runtime PASS' as result;
